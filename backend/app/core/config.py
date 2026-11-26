"""Application configuration loaded from environment variables / `.env`."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
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
    # Restrict origins in production (comma-separated or JSON array via env).
    cors_allow_origins: list[str] = Field(default_factory=lambda: ["*"])

    # --- OpenRouter AI Provider ---
    openrouter_api_key: str | None = None
    openrouter_model: str = "nvidia/nemotron-3.5-super-vl:free"
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    # Total time allowed for one AI call, in seconds.
    openrouter_timeout_seconds: float = Field(default=60.0, gt=0)
    openrouter_temperature: float = Field(default=0.4, ge=0, le=2)
    # Extra attempts when the AI returns malformed / invalid JSON.
    openrouter_max_retries: int = Field(default=1, ge=0, le=3)

    # --- Geocoding & Distance Feasibility (M3) ---
    nominatim_base_url: str = "https://nominatim.openstreetmap.org"
    # Nominatim usage policy forbids default HTTP library User-Agents.
    nominatim_user_agent: str = "AITravelPlanner/1.0.0 (contact@aitravelplanner.local)"
    # Nominatim public server allows max 1 request/second globally.
    nominatim_min_interval_seconds: float = Field(default=1.05, ge=0)
    geocoding_timeout_seconds: float = Field(default=10.0, gt=0)
    geocoding_cache_max_entries: int = Field(default=2000, ge=10)
    # Optional fallback using Google Places API (New) Text Search.
    google_places_api_key: str | None = None
    # Max reasonable distance (km) between consecutive activities on the same day.
    max_same_day_distance_km: float = Field(default=50.0, gt=0)
    average_travel_speed_kmh: float = Field(default=40.0, gt=0)

    # --- POI Discovery (Overpass API) ---
    overpass_base_url: str = "https://overpass-api.de/api/interpreter"
    overpass_timeout_seconds: float = Field(default=10.0, gt=0)
    poi_cache_ttl_seconds: int = Field(default=86400, ge=0)

    # --- Pluggable Hybrid Pricing Engine ---
    pricing_provider: Literal["free_web", "disabled"] = "free_web"
    pricing_search_url: str = "https://html.duckduckgo.com/html/"
    pricing_timeout_seconds: float = Field(default=4.0, gt=0)
    pricing_max_concurrency: int = Field(default=4, ge=1, le=10)
    pricing_cache_ttl_seconds: int = Field(default=86400, ge=0)

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
    rate_limit_weather: str = "60/hour"
    rate_limit_storage_uri: str = "memory://"
    # Only trust X-Forwarded-For when deployed behind a trusted reverse proxy.
    trust_proxy_headers: bool = False
    # Optional API key for X-API-Key header auth (strongly recommended in prod).
    api_key: str | None = None

    @field_validator(
        "nominatim_base_url",
        "overpass_base_url",
        "pricing_search_url",
        "weather_base_url",
        "openrouter_base_url",
    )
    @classmethod
    def upstream_urls_must_use_https(cls, value: str) -> str:
        allowed = (
            value.startswith("https://")
            or value.startswith("http://localhost")
            or value.startswith("http://127.0.0.1")
        )
        if not allowed:
            raise ValueError("Upstream API URLs must use https://")
        return value


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (overridable in tests)."""
    return Settings()
