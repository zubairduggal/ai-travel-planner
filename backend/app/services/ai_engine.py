"""Gemini API prompt builder & parser.

Flow:
1. Build the prompt from the trip request.
2. Ask Gemini for JSON constrained to `LLMItinerary` (structured output).
3. Validate the JSON with Pydantic; retry on malformed output.
4. Add server-side fields (trip_id, activity_id, totals) and return a
   validated `TripItineraryResponseSchema`.
"""

import asyncio
import logging
import uuid
from functools import lru_cache
from typing import Any

import httpx
from google import genai
from google.genai import errors as genai_errors
from google.genai import types
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
from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import (
    ActivitySchema,
    DayPlanSchema,
    TripItineraryResponseSchema,
)
from app.utils.prompt_templates import (
    ITINERARY_SYSTEM_INSTRUCTION,
    build_itinerary_prompt,
)

logger = logging.getLogger(__name__)


# --- Schemas Gemini must fill --------------------------------------------
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


# --- Engine ---------------------------------------------------------------


def _is_auth_error(exc: genai_errors.APIError) -> bool:
    """Gemini reports a bad key as 400 API_KEY_INVALID (or 401/403)."""
    if exc.code in (401, 403):
        return True
    text = f"{getattr(exc, 'message', '')} {getattr(exc, 'details', '')}"
    return exc.code == 400 and ("API_KEY_INVALID" in text or "API key" in text)


class AIEngine:
    """Generates itineraries with Google Gemini (`google-genai` SDK)."""

    def __init__(self, settings: Settings, client: Any | None = None) -> None:
        self._settings = settings
        if client is not None:
            self._client = client
        elif settings.gemini_api_key:
            self._client = genai.Client(
                api_key=settings.gemini_api_key,
                # HttpOptions.timeout is in milliseconds.
                http_options=types.HttpOptions(
                    timeout=int(settings.gemini_timeout_seconds * 1000)
                ),
            )
        else:
            self._client = None

    def _config(self) -> types.GenerateContentConfig:
        return types.GenerateContentConfig(
            system_instruction=ITINERARY_SYSTEM_INSTRUCTION,
            temperature=self._settings.gemini_temperature,
            response_mime_type="application/json",
            response_schema=LLMItinerary,
        )

    async def _call_gemini(self, prompt: str) -> str:
        """One Gemini request. Returns raw response text."""
        try:
            response = await asyncio.wait_for(
                self._client.aio.models.generate_content(
                    model=self._settings.gemini_model,
                    contents=prompt,
                    config=self._config(),
                ),
                timeout=self._settings.gemini_timeout_seconds,
            )
        except (asyncio.TimeoutError, httpx.TimeoutException) as exc:
            raise AITimeoutError() from exc
        except genai_errors.APIError as exc:
            logger.warning("Gemini API error %s: %s", exc.code, exc)
            if _is_auth_error(exc):
                raise AIAuthError() from exc
            if exc.code == 429:
                raise AIRateLimitError() from exc
            raise AIProviderError() from exc
        except httpx.HTTPError as exc:
            logger.warning("Gemini network error: %s", exc)
            raise AIProviderError("Could not reach the AI service.") from exc

        text = response.text
        if not text:
            # e.g. blocked by safety filters or empty candidate list.
            raise AIResponseError("The AI service returned an empty response.")
        return text

    @staticmethod
    def _parse(raw: str, trip: TripRequestSchema) -> LLMItinerary:
        """Validate Gemini JSON and check it matches the requested trip."""
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
        if self._client is None:
            raise AINotConfiguredError()

        prompt = build_itinerary_prompt(trip)
        attempts = 1 + self._settings.gemini_max_retries
        last_error: AIResponseError | None = None

        for attempt in range(1, attempts + 1):
            raw = await self._call_gemini(prompt)
            try:
                itinerary = self._parse(raw, trip)
            except AIResponseError as exc:
                logger.warning(
                    "Invalid itinerary from Gemini (attempt %d/%d): %s",
                    attempt,
                    attempts,
                    exc.message,
                )
                last_error = exc
                continue
            return self._to_response(itinerary, trip)

        assert last_error is not None
        raise last_error


@lru_cache
def _build_engine() -> AIEngine:
    return AIEngine(get_settings())


def get_ai_engine() -> AIEngine:
    """FastAPI dependency (overridden with a fake engine in tests)."""
    return _build_engine()
