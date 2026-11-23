"""Pydantic schemas for incoming client requests."""

import re
from datetime import date

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# Hard bounds protect Gemini token spend and Nominatim geocoding latency.
MAX_TRIP_DURATION_DAYS = 14
MAX_INTERESTS_COUNT = 15
MAX_INTEREST_LENGTH = 60
MAX_EXISTING_TITLES_COUNT = 50
MAX_TITLE_LENGTH = 150
MAX_BUDGET = 1_000_000.0

_CONTROL_CHARS_RE = re.compile(r"[\x00-\x1f\x7f]")


def _sanitize_text(value: str) -> str:
    """Strip ASCII control characters that could break logs or prompts."""
    return _CONTROL_CHARS_RE.sub(" ", value).strip()


class TripRequestSchema(BaseModel):
    """Payload for `POST /api/v1/itinerary/generate` (PRD section 4.1)."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        json_schema_extra={
            "example": {
                "destination": "Hunza Valley, Pakistan",
                "start_date": "2026-06-10",
                "end_date": "2026-06-14",
                "budget": 500.0,
                "currency": "USD",
                "interests": ["Nature", "Photography", "Local Food", "Hiking"],
                "travel_style": "Moderate",
            }
        },
    )

    destination: str = Field(..., min_length=1, max_length=200)
    start_date: date
    end_date: date
    budget: float = Field(..., gt=0, le=MAX_BUDGET, allow_inf_nan=False)
    currency: str = Field(..., min_length=3, max_length=3)
    interests: list[str] = Field(..., min_length=1, max_length=MAX_INTERESTS_COUNT)
    travel_style: str = Field(..., min_length=1, max_length=50)

    @field_validator("destination", "travel_style")
    @classmethod
    def sanitize_single_line_fields(cls, value: str) -> str:
        cleaned = _sanitize_text(value)
        if not cleaned:
            raise ValueError("Field must not be empty or control characters only")
        return cleaned

    @field_validator("currency")
    @classmethod
    def currency_must_be_alpha_code(cls, value: str) -> str:
        if not value.isalpha():
            raise ValueError("currency must be a 3-letter code, e.g. USD")
        return value.upper()

    @field_validator("interests")
    @classmethod
    def interests_must_not_be_blank(cls, value: list[str]) -> list[str]:
        cleaned = [_sanitize_text(item) for item in value if _sanitize_text(item)]
        if not cleaned:
            raise ValueError("interests must contain at least one non-empty item")
        if any(len(item) > MAX_INTEREST_LENGTH for item in cleaned):
            raise ValueError(
                f"Each interest must be at most {MAX_INTEREST_LENGTH} characters"
            )
        return cleaned

    @model_validator(mode="after")
    def validate_date_range(self) -> "TripRequestSchema":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        if self.duration_days > MAX_TRIP_DURATION_DAYS:
            raise ValueError(
                f"Trip duration cannot exceed {MAX_TRIP_DURATION_DAYS} days"
            )
        return self

    @property
    def duration_days(self) -> int:
        """Inclusive trip length: 2026-06-10 -> 2026-06-14 is 5 days."""
        return (self.end_date - self.start_date).days + 1


class RegenerateSlotRequestSchema(BaseModel):
    """Payload for `POST /api/v1/itinerary/regenerate-slot` (PRD M4)."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        json_schema_extra={
            "example": {
                "destination": "Hunza Valley, Pakistan",
                "day_number": 1,
                "time_slot": "Afternoon",
                "budget_remaining": 40.0,
                "currency": "USD",
                "interests": ["Nature", "Photography", "Local Food"],
                "travel_style": "Moderate",
                "existing_activity_titles": ["Visit Baltit Fort"],
                "activity_id": "act_02",
                "user_note": "Prefer a quiet viewpoint or café",
            }
        },
    )

    destination: str = Field(..., min_length=1, max_length=200)
    day_number: int = Field(..., ge=1, le=MAX_TRIP_DURATION_DAYS)
    time_slot: str = Field(..., min_length=1, max_length=50)
    budget_remaining: float = Field(..., ge=0, le=MAX_BUDGET, allow_inf_nan=False)
    currency: str = Field(..., min_length=3, max_length=3)
    interests: list[str] = Field(..., min_length=1, max_length=MAX_INTERESTS_COUNT)
    travel_style: str = Field(..., min_length=1, max_length=50)
    existing_activity_titles: list[str] = Field(
        default_factory=list, max_length=MAX_EXISTING_TITLES_COUNT
    )
    activity_id: str | None = Field(default=None, max_length=50)
    user_note: str | None = Field(default=None, max_length=300)

    @field_validator("destination", "time_slot", "travel_style")
    @classmethod
    def sanitize_required_text(cls, value: str) -> str:
        cleaned = _sanitize_text(value)
        if not cleaned:
            raise ValueError("Field must not be empty or control characters only")
        return cleaned

    @field_validator("user_note", "activity_id")
    @classmethod
    def sanitize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = _sanitize_text(value)
        return cleaned or None

    @field_validator("currency")
    @classmethod
    def currency_must_be_alpha_code(cls, value: str) -> str:
        if not value.isalpha():
            raise ValueError("currency must be a 3-letter code, e.g. USD")
        return value.upper()

    @field_validator("interests")
    @classmethod
    def interests_must_not_be_blank(cls, value: list[str]) -> list[str]:
        cleaned = [_sanitize_text(item) for item in value if _sanitize_text(item)]
        if not cleaned:
            raise ValueError("interests must contain at least one non-empty item")
        if any(len(item) > MAX_INTEREST_LENGTH for item in cleaned):
            raise ValueError(
                f"Each interest must be at most {MAX_INTEREST_LENGTH} characters"
            )
        return cleaned

    @field_validator("existing_activity_titles")
    @classmethod
    def sanitize_existing_titles(cls, value: list[str]) -> list[str]:
        cleaned = [_sanitize_text(item) for item in value if _sanitize_text(item)]
        if any(len(item) > MAX_TITLE_LENGTH for item in cleaned):
            raise ValueError(
                f"Each existing activity title must be at most "
                f"{MAX_TITLE_LENGTH} characters"
            )
        return cleaned
