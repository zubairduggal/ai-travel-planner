"""Pydantic schemas for incoming client requests."""

from datetime import date

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


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
    budget: float = Field(..., gt=0)
    currency: str = Field(..., min_length=3, max_length=3)
    interests: list[str] = Field(..., min_length=1)
    travel_style: str = Field(..., min_length=1, max_length=50)

    @field_validator("currency")
    @classmethod
    def currency_must_be_alpha_code(cls, value: str) -> str:
        if not value.isalpha():
            raise ValueError("currency must be a 3-letter code, e.g. USD")
        return value.upper()

    @field_validator("interests")
    @classmethod
    def interests_must_not_be_blank(cls, value: list[str]) -> list[str]:
        cleaned = [item.strip() for item in value if item.strip()]
        if not cleaned:
            raise ValueError("interests must contain at least one non-empty item")
        return cleaned

    @model_validator(mode="after")
    def end_date_not_before_start_date(self) -> "TripRequestSchema":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self

    @property
    def duration_days(self) -> int:
        """Inclusive trip length: 2026-06-10 -> 2026-06-14 is 5 days."""
        return (self.end_date - self.start_date).days + 1
