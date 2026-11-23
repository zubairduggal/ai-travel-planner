"""Pydantic schemas for JSON API responses."""

from datetime import datetime

from pydantic import BaseModel, Field


class ActivitySchema(BaseModel):
    """A single activity within a day (PRD section 4.1)."""

    activity_id: str
    time_slot: str
    title: str
    description: str
    category: str
    estimated_cost: float = Field(..., ge=0)
    # Coordinates are filled by the geocoding service (M3). Until a place is
    # verified they stay null instead of a fake 0.0, 0.0.
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    verified: bool = False


class DayPlanSchema(BaseModel):
    """One day of the itinerary."""

    day_number: int = Field(..., ge=1)
    title: str
    activities: list[ActivitySchema]


class TripItineraryResponseSchema(BaseModel):
    """Response for `POST /api/v1/itinerary/generate` (PRD section 4.1)."""

    trip_id: str
    destination: str
    duration_days: int = Field(..., ge=1)
    total_estimated_cost: float = Field(..., ge=0)
    currency: str = Field(..., min_length=3, max_length=3)
    days: list[DayPlanSchema]


class ErrorDetailSchema(BaseModel):
    code: str
    message: str


class ErrorResponseSchema(BaseModel):
    """Envelope used for all application errors."""

    error: ErrorDetailSchema


class HealthResponseSchema(BaseModel):
    """Response for `GET /api/v1/health` (PRD M1)."""

    status: str
    timestamp: datetime
    environment: str
