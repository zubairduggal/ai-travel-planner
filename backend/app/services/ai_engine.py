"""OpenRouter AI prompt builder & parser.

Flow:
1. Build the prompt from the trip (or slot regeneration) request.
2. Ask OpenRouter for JSON constrained to `LLMItinerary` or `LLMActivity`.
3. Validate the JSON with Pydantic; retry on malformed output.
4. Add server-side fields (trip_id, activity_id, totals) and return validated
   response schemas.
"""

import asyncio
import logging
import re
import uuid
from functools import lru_cache
from typing import Any

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
    TripItineraryResponseSchema,
)
from app.utils.prompt_templates import (
    ITINERARY_SYSTEM_INSTRUCTION,
    SLOT_SYSTEM_INSTRUCTION,
    build_itinerary_prompt,
    build_slot_regeneration_prompt,
)

logger = logging.getLogger(__name__)

_CODE_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


# --- Schemas the AI must fill --------------------------------------------
# Only the fields the model can know. IDs, totals and coordinates are added
# by the server (coordinates by the geocoding service in M3).


class LLMActivity(BaseModel):
    time_slot: str = Field(description="Morning, Afternoon or Evening")
    title: str = Field(description="Short title containing the real place name")
    description: str = Field(description="One or two sentences about the activity")
    category: str = Field(description="Short category, e.g. Historical, Nature")
    estimated_cost: float = Field(
        ge=0, description="Cost per person in the trip currency"
    )


class LLMDayPlan(BaseModel):
    day_number: int = Field(ge=1)
    title: str = Field(description="Short theme for the day")
    activities: list[LLMActivity] = Field(min_length=1)


class LLMItinerary(BaseModel):
    days: list[LLMDayPlan] = Field(min_length=1)


# --- Helpers --------------------------------------------------------------


def _enforce_strict_schema(node: Any) -> Any:
    """Add `additionalProperties: false` to object schemas for OpenRouter."""
    if isinstance(node, dict):
        result = {k: _enforce_strict_schema(v) for k, v in node.items()}
        if result.get("type") == "object" and "properties" in result:
            result.setdefault("additionalProperties", False)
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


# --- Engine ---------------------------------------------------------------


class AIEngine:
    """Generates itineraries and slot replacements via OpenRouter."""

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
        response_schema: type[BaseModel] = LLMItinerary,
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
        itinerary: LLMItinerary, trip: TripRequestSchema
    ) -> TripItineraryResponseSchema:
        """Add server-side IDs and totals."""
        counter = 0
        days: list[DayPlanSchema] = []
        for day in itinerary.days:
            activities = []
            for act in day.activities:
                counter += 1
                activities.append(
                    ActivitySchema(
                        activity_id=f"act_{counter:02d}",
                        time_slot=act.time_slot,
                        title=act.title,
                        description=act.description,
                        category=act.category,
                        estimated_cost=round(act.estimated_cost, 2),
                    )
                )
            days.append(
                DayPlanSchema(
                    day_number=day.day_number, title=day.title, activities=activities
                )
            )

        total = round(sum(a.estimated_cost for d in days for a in d.activities), 2)
        return TripItineraryResponseSchema(
            trip_id=f"itinerary_{uuid.uuid4().hex[:8]}",
            destination=trip.destination,
            duration_days=trip.duration_days,
            total_estimated_cost=total,
            currency=trip.currency,
            days=days,
        )

    async def generate_itinerary(
        self, trip: TripRequestSchema
    ) -> TripItineraryResponseSchema:
        if not self._is_configured():
            raise AINotConfiguredError()

        prompt = build_itinerary_prompt(trip)
        attempts = 1 + self._settings.openrouter_max_retries
        last_error: AIResponseError | None = None

        for attempt in range(1, attempts + 1):
            raw = await self._call_openrouter(
                prompt,
                system_instruction=ITINERARY_SYSTEM_INSTRUCTION,
                response_schema=LLMItinerary,
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
            return self._to_response(itinerary, trip)

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
    """FastAPI dependency (overridden with a fake engine in tests)."""
    return _build_engine()
