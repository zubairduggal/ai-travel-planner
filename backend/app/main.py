"""FastAPI application setup, OpenAPI metadata, lifespan & security middleware."""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from slowapi.errors import RateLimitExceeded

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.exceptions import register_exception_handlers
from app.core.security import limiter, rate_limit_exceeded_handler
from app.services.cache_service import _build_cache_service

logger = logging.getLogger(__name__)

OPENAPI_TAGS = [
    {
        "name": "Health",
        "description": "Server status and readiness checks.",
    },
    {
        "name": "Itinerary",
        "description": (
            "AI-powered itinerary generation (cached, rate-limited, geocoded) "
            "and single-slot regeneration."
        ),
    },
    {
        "name": "Weather",
        "description": "Daily destination weather forecasts powered by Open-Meteo.",
    },
]

APP_DESCRIPTION = (
    "FastAPI backend for the AI-Powered Travel Planner Flutter client. "
    "Generates day-by-day itineraries using OpenRouter, verifies locations "
    "with OpenStreetMap Nominatim (and optional Google Places fallback), "
    "validates same-day travel feasibility using Haversine distances, and "
    "protects resources with DiskCache/Redis caching, SlowAPI rate limiting, "
    "and optional X-API-Key authentication."
)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Application startup/shutdown lifecycle."""
    settings = get_settings()
    if settings.app_env == "production" and not settings.api_key:
        logger.warning(
            "API_KEY is not configured in production; protected endpoints are open."
        )
    try:
        yield
    finally:
        if _build_cache_service.cache_info().currsize > 0:
            await _build_cache_service().close()


def create_app() -> FastAPI:
    settings = get_settings()
    is_production = settings.app_env == "production"

    application = FastAPI(
        title=settings.app_name,
        description=APP_DESCRIPTION,
        version=settings.app_version,
        debug=settings.debug,
        openapi_tags=OPENAPI_TAGS,
        docs_url=None if is_production else "/docs",
        redoc_url=None if is_production else "/redoc",
        openapi_url=None if is_production else "/openapi.json",
        lifespan=lifespan,
    )

    @application.middleware("http")
    async def add_security_headers(request: Request, call_next) -> Response:
        response: Response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        return response

    # Mobile (Flutter) clients do not send browser CORS preflights, but this
    # keeps Flutter Web / Swagger testing working while letting production
    # restrict origins via CORS_ALLOW_ORIGINS.
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allow_origins,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Content-Type", "X-API-Key"],
    )

    application.state.limiter = limiter
    application.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
    register_exception_handlers(application)
    application.include_router(api_router, prefix=settings.api_v1_prefix)
    return application


app = create_app()
