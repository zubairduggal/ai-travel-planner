"""Application configuration loaded from environment variables / `.env`."""

from functools import lru_cache
from typing import Literal

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
    app_version: str = "0.1.0"
    app_env: Literal["development", "staging", "production"] = "development"
    debug: bool = False
    api_v1_prefix: str = "/api/v1"


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (overridable in tests)."""
    return Settings()
