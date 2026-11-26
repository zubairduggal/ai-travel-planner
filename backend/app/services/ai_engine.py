"""OpenRouter AI prompt builder, grounded post-processor & parser.

Flow:
1. Build the prompt from the trip (and optional verified OSM POIs).
2. Ask OpenRouter for JSON constrained to `LLMItineraryStrict` or `LLMActivity`.
3. Validate the JSON with Pydantic; retry on malformed output.
4. Enforce travel-mode fidelity (zero airport slots on ground modes), attach
   verified GPS coordinates from discovered POIs, select sensible defaults,
   and return validated response schemas.
"""

import asyncio
from functools import lru_cache
import logging
import re
from typing import Any, Literal
import uuid

import httpx
from pydantic import BaseModel, Field, ValidationError

from app.core.config import Settings, get_settings
from app.core.exceptions import (
    AIAuthError,
    AINotConfiguredError,
    AIProviderError,
    AIRateLimitError,
    AIResponseError,
    AITimeoutError,
)
from app.models.request_schemas import RegenerateSlotRequestSchema, TripRequestSchema
from app.models.response_schemas import (
    ActivitySchema,
    DayPlanSchema,
    PlaceOption,
    TransportSummary,
    TripItineraryResponseSchema,
)
from app.services.geocoding_service import extract_place_name
from app.services.poi_discovery_service import DestinationPOIBundle, DiscoveredPOI
from app.utils.prompt_templates import (
    ITINERARY_SYSTEM_INSTRUCTION,
    SLOT_SYSTEM_INSTRUCTION,
    build_itinerary_prompt,
    build_slot_regeneration_prompt,
)

logger = logging.getLogger(__name__)

_CODE_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)
_AIRPORT_ACTIVITY_RE = re.compile(
    r"\b(airport|flight|boarding|airfield|terminal\s+\d+)\b",
    re.IGNORECASE,
)

MAX_HOTEL_OPTIONS = 4
MAX_DINING_OPTIONS = 6


# --- Schemas the AI must fill --------------------------------------------


class LLMActivity(BaseModel):
    time_slot: str = Field(description="Morning, Afternoon or Evening")
    title: str = Field(description="Concise real-world landmark or place name")
    description: str = Field(description="One or two sentences about the activity")
    category: str = Field(description="Short category, e.g. Historical, Nature")
    estimated_cost: float = Field(
        ge=0, description="Cost per person in the trip currency"
    )


class LLMDayPlan(BaseModel):
    day_number: int = Field(ge=1)
    title: str = Field(description="Short theme for the day")
    activities: list[LLMActivity] = Field(min_length=1)


class LLMTransportSummary(BaseModel):
    mode: str = Field(description="Travel mode: air, road, train, bus, or bike")
    estimated_cost: float = Field(
        ge=0, description="Estimated round-trip transport cost in trip currency"
    )
    notes: str = Field(description="Brief breakdown of transport logistics")
    route_tip: str = Field(description="Practical route, highway, or booking tip")


class LLMPlaceOption(BaseModel):
    name: str = Field(description="Exact real place name from verified_real_places")
    tier: Literal["budget", "mid_range", "comfort"] = Field(
        description="Price tier: budget, mid_range, or comfort"
    )
    estimated_price: float = Field(
        ge=0, description="Per-night hotel price or per-person meal price"
    )
    price_note: str = Field(description="Short estimate note, e.g. Est. per night")
    highlights: list[str] = Field(
        description="2-3 concise highlights for this hotel or restaurant"
    )


class LLMItineraryStrict(BaseModel):
    """Strict schema sent to OpenRouter response_format (all fields required)."""

    days: list[LLMDayPlan] = Field(min_length=1)
    transport_summary: LLMTransportSummary
    hotel_options: list[LLMPlaceOption]
    dining_options: list[LLMPlaceOption]


class LLMItinerary(BaseModel):
    """Parser schema accepting both full Phase 2 JSON and minimal legacy JSON."""

    days: list[LLMDayPlan] = Field(min_length=1)
    transport_summary: LLMTransportSummary | None = None
    hotel_options: list[LLMPlaceOption] = Field(default_factory=list)
    dining_options: list[LLMPlaceOption] = Field(default_factory=list)


# --- Helpers --------------------------------------------------------------


def _enforce_strict_schema(node: Any) -> Any:
    """Add `additionalProperties: false` and explicit `required` for OpenRouter."""
    if isinstance(node, dict):
        result = {k: _enforce_strict_schema(v) for k, v in node.items()}
        if result.get("type") == "object" and "properties" in result:
            result["additionalProperties"] = False
            result["required"] = list(result["properties"].keys())
        return result
    if isinstance(node, list):
        return [_enforce_strict_schema(item) for item in node]
    return node


def _build_openrouter_response_format(
    response_schema: type[BaseModel],
) -> dict[str, Any]:
    """Build an OpenAI-compatible strict json_schema response_format."""
    schema = _enforce_strict_schema(response_schema.model_json_schema())
    return {
        "type": "json_schema",
        "json_schema": {
            "name": response_schema.__name__,
            "strict": True,
            "schema": schema,
        },
    }


def _strip_code_fences(raw: str) -> str:
    """Remove optional ```json ... ``` fences if a provider wraps its JSON."""
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = _CODE_FENCE_RE.sub("", cleaned).strip()
    return cleaned


def _norm_key(name: str) -> str:
    return " ".join(name.strip().lower().split())


def _preferred_tier(travel_style: str) -> Literal["budget", "mid_range", "comfort"]:
    lower = travel_style.strip().lower()
    if "budget" in lower:
        return "budget"
    if "luxury" in lower or "comfort" in lower:
        return "comfort"
    return "mid_range"


def _build_poi_lookup(
    poi_bundle: DestinationPOIBundle | None,
) -> dict[str, DiscoveredPOI]:
    if poi_bundle is None:
        return {}
    lookup: dict[str, DiscoveredPOI] = {}
    for poi in poi_bundle.hotels + poi_bundle.dining + poi_bundle.attractions:
        lookup.setdefault(_norm_key(poi.name), poi)
    return lookup


def _match_poi(title: str, lookup: dict[str, DiscoveredPOI]) -> DiscoveredPOI | None:
    if not lookup:
        return None
    for candidate in (title, extract_place_name(title)):
        key = _norm_key(candidate)
        if key in lookup:
            return lookup[key]
    return None


def _is_airport_activity(act: LLMActivity) -> bool:
    return bool(
        _AIRPORT_ACTIVITY_RE.search(act.title)
        or _AIRPORT_ACTIVITY_RE.search(act.description)
    )


def _fallback_ground_activity(trip: TripRequestSchema, day_number: int) -> LLMActivity:
    origin = trip.departure_city or "your departure city"
    mode_label = {
        "road": "Road drive",
        "train": "Train journey",
        "bus": "Intercity bus journey",
        "bike": "Motorcycle ride",
    }.get(trip.travel_mode, "Overland journey")
    if day_number == 1:
        return LLMActivity(
            time_slot="Morning",
            title=trip.destination,
            description=(
                f"{mode_label} from {origin} into {trip.destination}, "
                f"check in to your stay, and refresh before exploring."
            ),
            category="Travel",
            estimated_cost=0.0,
        )
    return LLMActivity(
        time_slot="Evening",
        title=trip.destination,
        description=(
            f"Wrap up sightseeing and begin your return {mode_label.lower()} "
            f"toward {origin}."
        ),
        category="Travel",
        estimated_cost=0.0,
    )


def _build_place_options(
    *,
    llm_options: list[LLMPlaceOption],
    fallback_pois: list[DiscoveredPOI],
    poi_lookup: dict[str, DiscoveredPOI],
    prefix: str,
    max_items: int,
    multiplier: int,
    travel_style: str,
    default_selected_count: int,
    unit_label: str,
) -> list[PlaceOption]:
    """Build grounded PlaceOptions with verified GPS and default selections."""
    options: list[PlaceOption] = []
    seen_names: set[str] = set()

    for item in llm_options:
        if len(options) >= max_items:
            break
        key = _norm_key(item.name)
        if not key or key in seen_names:
            continue
        seen_names.add(key)
        poi = _match_poi(item.name, poi_lookup)
        price = round(item.estimated_price, 2)
        options.append(
            PlaceOption(
                option_id=f"{prefix}_{len(options) + 1:02d}",
                name=poi.name if poi else item.name.strip(),
                tier=item.tier,
                estimated_price=price,
                total_estimated_cost=round(price * multiplier, 2),
                price_source="ai_estimated",
                price_note=item.price_note.strip() or f"Est. per {unit_label}",
                latitude=poi.latitude if poi else None,
                longitude=poi.longitude if poi else None,
                verified=poi is not None,
                distance_to_center_km=poi.distance_to_center_km if poi else None,
                highlights=[h.strip() for h in item.highlights if h.strip()][:4],
                selected=False,
            )
        )

    # Top up from verified POIs if the LLM returned fewer options than available.
    tiers: list[Literal["budget", "mid_range", "comfort"]] = [
        "budget",
        "mid_range",
        "comfort",
    ]
    if not options and fallback_pois:
        for poi in fallback_pois[: min(3, max_items)]:
            key = _norm_key(poi.name)
            if key in seen_names:
                continue
            seen_names.add(key)
            tier = tiers[len(options) % len(tiers)]
            options.append(
                PlaceOption(
                    option_id=f"{prefix}_{len(options) + 1:02d}",
                    name=poi.name,
                    tier=tier,
                    estimated_price=0.0,
                    total_estimated_cost=0.0,
                    price_source="ai_estimated",
                    price_note=f"Estimated per {unit_label}",
                    latitude=poi.latitude,
                    longitude=poi.longitude,
                    verified=True,
                    distance_to_center_km=poi.distance_to_center_km,
                    highlights=(
                        [poi.subcategory.replace("_", " ").title()]
                        if poi.subcategory
                        else []
                    ),
                    selected=False,
                )
            )

    if options and default_selected_count > 0:
        pref_tier = _preferred_tier(travel_style)
        selected_indices: list[int] = []
        for idx, opt in enumerate(options):
            if opt.tier == pref_tier and len(selected_indices) < default_selected_count:
                selected_indices.append(idx)
        for idx in range(len(options)):
            if len(selected_indices) >= default_selected_count:
                break
            if idx not in selected_indices:
                selected_indices.append(idx)
        for idx in selected_indices:
            options[idx] = options[idx].model_copy(update={"selected": True})

    return options


# --- Engine ---------------------------------------------------------------


class AIEngine:
    """Generates grounded itineraries and slot replacements via OpenRouter."""

    def __init__(
        self,
        settings: Settings,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._settings = settings
        self._http_client = http_client

    def _is_configured(self) -> bool:
        return bool(self._settings.openrouter_api_key)

    async def _call_openrouter(
        self,
        prompt: str,
        *,
        system_instruction: str = ITINERARY_SYSTEM_INSTRUCTION,
        response_schema: type[BaseModel] = LLMItineraryStrict,
    ) -> str:
        """Call OpenRouter's OpenAI-compatible chat completions endpoint."""
        url = f"{self._settings.openrouter_base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self._settings.openrouter_api_key}",
            "Content-Type": "application/json",
            "X-Title": self._settings.app_name,
        }
        body: dict[str, Any] = {
            "model": self._settings.openrouter_model,
            "temperature": self._settings.openrouter_temperature,
            "messages": [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": prompt},
            ],
            "response_format": _build_openrouter_response_format(response_schema),
        }

        try:
            if self._http_client is not None:
                response = await asyncio.wait_for(
                    self._http_client.post(
                        url,
                        json=body,
                        headers=headers,
                        timeout=self._settings.openrouter_timeout_seconds,
                        follow_redirects=False,
                    ),
                    timeout=self._settings.openrouter_timeout_seconds,
                )
            else:
                async with httpx.AsyncClient(
                    timeout=self._settings.openrouter_timeout_seconds,
                    follow_redirects=False,
                ) as client:
                    response = await asyncio.wait_for(
                        client.post(url, json=body, headers=headers),
                        timeout=self._settings.openrouter_timeout_seconds,
                    )
        except (asyncio.TimeoutError, httpx.TimeoutException) as exc:
            raise AITimeoutError() from exc
        except httpx.HTTPError as exc:
            logger.warning("OpenRouter network error: %s", type(exc).__name__)
            raise AIProviderError("Could not reach the AI service.") from exc

        status = response.status_code
        if status in (401, 403):
            logger.warning(
                "OpenRouter auth error model=%s status=%s",
                self._settings.openrouter_model,
                status,
            )
            raise AIAuthError()
        if status in (402, 429):
            logger.warning(
                "OpenRouter quota/rate error model=%s status=%s",
                self._settings.openrouter_model,
                status,
            )
            raise AIRateLimitError()
        if status >= 400:
            logger.warning(
                "OpenRouter API error model=%s status=%s",
                self._settings.openrouter_model,
                status,
            )
            raise AIProviderError()

        try:
            payload = response.json()
            choices = payload.get("choices") if isinstance(payload, dict) else None
            message = (
                choices[0].get("message")
                if isinstance(choices, list) and choices
                else None
            )
            content = message.get("content") if isinstance(message, dict) else None
        except (ValueError, KeyError, TypeError, AttributeError) as exc:
            raise AIResponseError(
                "The AI service returned an invalid response."
            ) from exc

        if not isinstance(content, str) or not content.strip():
            raise AIResponseError("The AI service returned an empty response.")
        return _strip_code_fences(content)

    @staticmethod
    def _parse(raw: str, trip: TripRequestSchema) -> LLMItinerary:
        """Validate AI JSON and check it matches the requested trip."""
        try:
            itinerary = LLMItinerary.model_validate_json(raw)
        except ValidationError as exc:
            raise AIResponseError() from exc

        day_numbers = [day.day_number for day in itinerary.days]
        expected = list(range(1, trip.duration_days + 1))
        if sorted(day_numbers) != expected:
            raise AIResponseError(
                f"The AI returned days {day_numbers}, expected {expected}."
            )
        itinerary.days.sort(key=lambda day: day.day_number)
        return itinerary

    @staticmethod
    def _to_response(
        itinerary: LLMItinerary,
        trip: TripRequestSchema,
        poi_bundle: DestinationPOIBundle | None = None,
    ) -> TripItineraryResponseSchema:
        """Add server-side IDs, ground GPS from POIs, enforce mode fidelity & totals."""
        poi_lookup = _build_poi_lookup(poi_bundle)
        counter = 0
        days: list[DayPlanSchema] = []
        for day in itinerary.days:
            raw_acts = list(day.activities)
            if trip.travel_mode != "air":
                filtered = [a for a in raw_acts if not _is_airport_activity(a)]
                raw_acts = filtered or [_fallback_ground_activity(trip, day.day_number)]

            activities: list[ActivitySchema] = []
            for act in raw_acts:
                counter += 1
                poi = _match_poi(act.title, poi_lookup)
                activities.append(
                    ActivitySchema(
                        activity_id=f"act_{counter:02d}",
                        time_slot=act.time_slot,
                        title=act.title,
                        description=act.description,
                        category=act.category,
                        estimated_cost=round(act.estimated_cost, 2),
                        latitude=poi.latitude if poi else None,
                        longitude=poi.longitude if poi else None,
                        verified=poi is not None,
                    )
                )
            days.append(
                DayPlanSchema(
                    day_number=day.day_number, title=day.title, activities=activities
                )
            )

        transport_summary: TransportSummary | None = None
        if itinerary.transport_summary is not None:
            transport_summary = TransportSummary(
                mode=trip.travel_mode,
                estimated_cost=round(itinerary.transport_summary.estimated_cost, 2),
                price_source="ai_estimated",
                notes=itinerary.transport_summary.notes.strip(),
                route_tip=itinerary.transport_summary.route_tip.strip(),
            )

        nights = max(1, trip.duration_days - 1) if trip.duration_days > 1 else 1
        hotel_options = _build_place_options(
            llm_options=itinerary.hotel_options,
            fallback_pois=poi_bundle.hotels if poi_bundle else [],
            poi_lookup=poi_lookup,
            prefix="hotel",
            max_items=MAX_HOTEL_OPTIONS,
            multiplier=nights,
            travel_style=trip.travel_style,
            default_selected_count=1,
            unit_label="night",
        )
        dining_options = _build_place_options(
            llm_options=itinerary.dining_options,
            fallback_pois=poi_bundle.dining if poi_bundle else [],
            poi_lookup=poi_lookup,
            prefix="dining",
            max_items=MAX_DINING_OPTIONS,
            multiplier=1,
            travel_style=trip.travel_style,
            default_selected_count=min(2, trip.duration_days),
            unit_label="meal",
        )

        total = round(sum(a.estimated_cost for d in days for a in d.activities), 2)
        return TripItineraryResponseSchema(
            trip_id=f"itinerary_{uuid.uuid4().hex[:8]}",
            destination=trip.destination,
            duration_days=trip.duration_days,
            total_estimated_cost=total,
            currency=trip.currency,
            days=days,
            travel_mode=trip.travel_mode,
            transport_summary=transport_summary,
            hotel_options=hotel_options,
            dining_options=dining_options,
        )

    async def generate_itinerary(
        self,
        trip: TripRequestSchema,
        *,
        poi_bundle: DestinationPOIBundle | None = None,
    ) -> TripItineraryResponseSchema:
        if not self._is_configured():
            raise AINotConfiguredError()

        prompt = build_itinerary_prompt(trip, poi_bundle=poi_bundle)
        attempts = 1 + self._settings.openrouter_max_retries
        last_error: AIResponseError | None = None

        for attempt in range(1, attempts + 1):
            raw = await self._call_openrouter(
                prompt,
                system_instruction=ITINERARY_SYSTEM_INSTRUCTION,
                response_schema=LLMItineraryStrict,
            )
            try:
                itinerary = self._parse(raw, trip)
            except AIResponseError as exc:
                logger.warning(
                    "Invalid itinerary from OpenRouter (attempt %d/%d): %s",
                    attempt,
                    attempts,
                    exc.message,
                )
                last_error = exc
                continue
            return self._to_response(itinerary, trip, poi_bundle=poi_bundle)

        raise last_error or AIResponseError()

    async def regenerate_slot(
        self, slot_req: RegenerateSlotRequestSchema
    ) -> ActivitySchema:
        """Generate a single replacement activity without regenerating the trip."""
        if not self._is_configured():
            raise AINotConfiguredError()

        prompt = build_slot_regeneration_prompt(slot_req)
        attempts = 1 + self._settings.openrouter_max_retries
        last_error: AIResponseError | None = None

        for attempt in range(1, attempts + 1):
            raw = await self._call_openrouter(
                prompt,
                system_instruction=SLOT_SYSTEM_INSTRUCTION,
                response_schema=LLMActivity,
            )
            try:
                llm_act = LLMActivity.model_validate_json(raw)
            except ValidationError as exc:
                logger.warning(
                    "Invalid slot activity from OpenRouter (attempt %d/%d): %s",
                    attempt,
                    attempts,
                    exc,
                )
                last_error = AIResponseError(
                    "The AI service returned an invalid replacement activity."
                )
                continue

            return ActivitySchema(
                activity_id=slot_req.activity_id or f"act_{uuid.uuid4().hex[:6]}",
                time_slot=slot_req.time_slot,
                title=llm_act.title,
                description=llm_act.description,
                category=llm_act.category,
                estimated_cost=round(llm_act.estimated_cost, 2),
            )

        raise last_error or AIResponseError()


@lru_cache
def _build_engine() -> AIEngine:
    return AIEngine(get_settings())


def get_ai_engine() -> AIEngine:
    """FastAPI dependency (overridable with a fake engine in tests)."""
    return _build_engine()
