"""Trip generation & slot regeneration endpoints (M2 + M3 + M4)."""

from fastapi import APIRouter, Depends, Request, Response

from app.core.security import (
    _itinerary_rate_limit,
    _regenerate_slot_rate_limit,
    limiter,
    verify_api_key,
)
from app.models.request_schemas import RegenerateSlotRequestSchema, TripRequestSchema
from app.models.response_schemas import (
    ActivitySchema,
    ErrorResponseSchema,
    TripItineraryResponseSchema,
)
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.cache_service import CacheService, get_cache_service
from app.services.geocoding_service import GeocodingService, get_geocoding_service

router = APIRouter(prefix="/itinerary", tags=["Itinerary"])

_ERRORS = {
    401: {"model": ErrorResponseSchema, "description": "Missing or invalid X-API-Key"},
    429: {"model": ErrorResponseSchema, "description": "Daily rate limit exceeded"},
    502: {"model": ErrorResponseSchema, "description": "AI returned an error/invalid itinerary"},
    503: {"model": ErrorResponseSchema, "description": "AI not configured, auth failed or over quota"},
    504: {"model": ErrorResponseSchema, "description": "AI request timed out"},
}


@router.post(
    "/generate",
    response_model=TripItineraryResponseSchema,
    responses=_ERRORS,
    dependencies=[Depends(verify_api_key)],
    summary="Generate a day-by-day itinerary",
)
@limiter.limit(_itinerary_rate_limit)
async def generate_itinerary(
    request: Request,
    response: Response,
    trip: TripRequestSchema,
    engine: AIEngine = Depends(get_ai_engine),
    geocoder: GeocodingService = Depends(get_geocoding_service),
    cache: CacheService = Depends(get_cache_service),
) -> TripItineraryResponseSchema:
    """Generate a cached, geocoded day-by-day itinerary with Google Gemini."""
    cached = await cache.get_itinerary(trip)
    if cached is not None:
        response.headers["X-Cache"] = "HIT"
        return cached

    itinerary = await engine.generate_itinerary(trip)
    verified = await geocoder.verify_itinerary(itinerary)
    await cache.set_itinerary(trip, verified)
    response.headers["X-Cache"] = "MISS"
    return verified


@router.post(
    "/regenerate-slot",
    response_model=ActivitySchema,
    responses=_ERRORS,
    dependencies=[Depends(verify_api_key)],
    summary="Regenerate a single activity slot",
)
@limiter.limit(_regenerate_slot_rate_limit)
async def regenerate_slot(
    request: Request,
    slot_request: RegenerateSlotRequestSchema,
    engine: AIEngine = Depends(get_ai_engine),
    geocoder: GeocodingService = Depends(get_geocoding_service),
) -> ActivitySchema:
    """Replace a single activity slot without regenerating the full itinerary."""
    activity = await engine.regenerate_slot(slot_request)
    dest_loc = await geocoder.geocode_place(slot_request.destination)
    dest_viewbox = dest_loc.boundingbox if dest_loc else None
    return await geocoder.verify_activity(
        activity, destination=slot_request.destination, viewbox=dest_viewbox
    )
