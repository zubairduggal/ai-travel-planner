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
    app_version: str = "0.2.0"
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


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (overridable in tests)."""
    return Settings()
