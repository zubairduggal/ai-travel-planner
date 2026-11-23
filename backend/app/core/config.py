"""Application configuration loaded from environment variables / `.env`."""

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed application settings.

    Values are read (case-insensitively) from environment variables first,
    then from a `.env` file in the working directory, then the defaults below.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "AI Travel Planner API"
    app_version: str = "1.0.0"
    app_env: Literal["development", "staging", "production"] = "development"
    debug: bool = False
    api_v1_prefix: str = "/api/v1"

    # --- Gemini (M2) ---
    gemini_api_key: str | None = None
    # Current stable Flash model per ai.google.dev deprecations page (Nov 2026).
    gemini_model: str = "gemini-3.8-flash"
    # Total time allowed for one Gemini call, in seconds.
    gemini_timeout_seconds: float = Field(default=60.0, gt=0)
    gemini_temperature: float = Field(default=0.4, ge=0, le=2)
    # Extra attempts when Gemini returns malformed / invalid JSON.
    gemini_max_retries: int = Field(default=1, ge=0, le=3)

    # --- Geocoding & Distance Feasibility (M3) ---
    nominatim_base_url: str = "https://nominatim.openstreetmap.org"
    # Nominatim usage policy forbids default HTTP library User-Agents.
    nominatim_user_agent: str = "AITravelPlanner/1.0.0 (contact@aitravelplanner.local)"
    # Nominatim public server allows max 1 request/second globally.
    nominatim_min_interval_seconds: float = Field(default=1.05, ge=0)
    geocoding_timeout_seconds: float = Field(default=10.0, gt=0)
    # Optional fallback using Google Places API (New) Text Search.
    google_places_api_key: str | None = None
    # Max reasonable distance (km) between consecutive activities on the same day.
    max_same_day_distance_km: float = Field(default=50.0, gt=0)
    average_travel_speed_kmh: float = Field(default=40.0, gt=0)

    # --- Weather Proxy (M3, Open-Meteo) ---
    weather_base_url: str = "https://api.open-meteo.com/v1/forecast"
    weather_timeout_seconds: float = Field(default=10.0, gt=0)

    # --- Caching (M4) ---
    cache_backend: Literal["disk", "redis", "memory"] = "disk"
    diskcache_dir: str = ".cache/itineraries"
    redis_url: str = "redis://localhost:6379/0"
    cache_ttl_seconds: int = Field(default=86400, ge=0)

    # --- Rate Limiting & API Key Security (M4) ---
    rate_limit_itinerary: str = "5/day"
    rate_limit_regenerate_slot: str = "20/day"
    rate_limit_storage_uri: str = "memory://"
    # Optional API key for X-API-Key header auth (enforced when set).
    api_key: str | None = None


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (overridable in tests)."""
    return Settings()
