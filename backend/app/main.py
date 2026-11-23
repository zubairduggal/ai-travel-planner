"""FastAPI application setup, OpenAPI metadata, lifespan & middleware."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi.errors import RateLimitExceeded

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.exceptions import register_exception_handlers
from app.core.security import limiter, rate_limit_exceeded_handler

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
    "Generates day-by-day itineraries using Google Gemini, verifies locations "
    "with OpenStreetMap Nominatim (and optional Google Places fallback), "
    "validates same-day travel feasibility using Haversine distances, and "
    "protects resources with DiskCache/Redis caching, SlowAPI rate limiting, "
    "and optional X-API-Key authentication."
)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Application startup/shutdown lifecycle."""
    yield


def create_app() -> FastAPI:
    settings = get_settings()

    application = FastAPI(
        title=settings.app_name,
        description=APP_DESCRIPTION,
        version=settings.app_version,
        debug=settings.debug,
        openapi_tags=OPENAPI_TAGS,
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # Mobile (Flutter) clients do not send browser CORS preflights, but this
    # keeps Flutter Web / Swagger testing working during development.
    application.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    application.state.limiter = limiter
    application.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
    register_exception_handlers(application)
    application.include_router(api_router, prefix=settings.api_v1_prefix)
    return application


app = create_app()
