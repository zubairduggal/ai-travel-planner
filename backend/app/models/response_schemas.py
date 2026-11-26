"""Pydantic schemas for JSON API responses."""

from datetime import date, datetime
from typing import Literal

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
    # Populated by the Haversine feasibility check (M3).
    total_distance_km: float | None = Field(default=None, ge=0)
    feasible: bool = True
    distance_warnings: list[str] = Field(default_factory=list)


class TransportSummary(BaseModel):
    """High-level transport estimate and routing guidance for the chosen mode."""

    mode: str
    estimated_cost: float = Field(..., ge=0)
    price_source: Literal["web_found", "ai_estimated"] = "ai_estimated"
    notes: str = ""
    route_tip: str = ""


class PlaceOption(BaseModel):
    """Comparable real-world stay or dining option with verified GPS metadata."""

    option_id: str
    name: str
    tier: Literal["budget", "mid_range", "comfort"]
    estimated_price: float = Field(..., ge=0)
    total_estimated_cost: float = Field(..., ge=0)
    price_source: Literal["web_found", "ai_estimated"] = "ai_estimated"
    price_note: str = ""
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    verified: bool = False
    distance_to_center_km: float | None = Field(default=None, ge=0)
    highlights: list[str] = Field(default_factory=list)
    selected: bool = False


class TripItineraryResponseSchema(BaseModel):
    """Response for `POST /api/v1/itinerary/generate` (PRD section 4.1)."""

    trip_id: str
    destination: str
    duration_days: int = Field(..., ge=1)
    total_estimated_cost: float = Field(..., ge=0)
    currency: str = Field(default="PKR", min_length=3, max_length=3)
    days: list[DayPlanSchema]
    travel_mode: str = "air"
    transport_summary: TransportSummary | None = None
    hotel_options: list[PlaceOption] = Field(default_factory=list)
    dining_options: list[PlaceOption] = Field(default_factory=list)


# Alias for callers referencing the concise schema name.
ItineraryResponseSchema = TripItineraryResponseSchema


class DailyWeatherSchema(BaseModel):
    """Single day's weather forecast from Open-Meteo."""

    date: date
    temp_max_c: float | None = None
    temp_min_c: float | None = None
    precipitation_probability_max: int | None = Field(default=None, ge=0, le=100)
    weather_code: int | None = None
    condition: str


class WeatherResponseSchema(BaseModel):
    """Response for `GET /api/v1/weather`."""

    latitude: float
    longitude: float
    timezone: str
    daily: list[DailyWeatherSchema]


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
