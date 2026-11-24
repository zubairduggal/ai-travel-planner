"""Weather & utilities proxy endpoint using Open-Meteo (no API key required)."""

import httpx
from fastapi import APIRouter, Depends, Query, Request

from app.core.config import Settings, get_settings
from app.core.security import _weather_rate_limit, limiter, verify_api_key
from app.models.response_schemas import ErrorResponseSchema, WeatherResponseSchema
from app.services.weather_service import (
    WMO_WEATHER_CODES,
    describe_weather_code,
    fetch_weather_forecast,
)

__all__ = [
    "WMO_WEATHER_CODES",
    "describe_weather_code",
    "get_weather_forecast",
    "get_weather_http_client",
    "router",
]

router = APIRouter(prefix="/weather", tags=["Weather"])


async def get_weather_http_client() -> httpx.AsyncClient | None:
    """Dependency hook so tests can inject a mocked httpx.AsyncClient."""
    return None


@router.get(
    "",
    response_model=WeatherResponseSchema,
    dependencies=[Depends(verify_api_key)],
    responses={
        401: {
            "model": ErrorResponseSchema,
            "description": "Missing or invalid API key",
        },
        429: {"model": ErrorResponseSchema, "description": "Rate limit exceeded"},
        502: {"model": ErrorResponseSchema, "description": "Weather provider error"},
        504: {"model": ErrorResponseSchema, "description": "Weather provider timeout"},
    },
    summary="Get daily weather forecast for a coordinate",
)
@limiter.limit(_weather_rate_limit)
async def get_weather_forecast(
    request: Request,
    lat: float = Query(..., ge=-90, le=90, description="Latitude (WGS84)"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude (WGS84)"),
    days: int = Query(default=5, ge=1, le=16, description="Number of forecast days"),
    settings: Settings = Depends(get_settings),
    http_client: httpx.AsyncClient | None = Depends(get_weather_http_client),
) -> WeatherResponseSchema:
    """Fetch a daily weather forecast from Open-Meteo for the given coordinates."""
    return await fetch_weather_forecast(
        lat=lat,
        lon=lon,
        days=days,
        settings=settings,
        http_client=http_client,
    )
