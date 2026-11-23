"""Trip generation endpoints."""

from fastapi import APIRouter, Depends

from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import ErrorResponseSchema, TripItineraryResponseSchema
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.geocoding_service import GeocodingService, get_geocoding_service

router = APIRouter(prefix="/itinerary", tags=["Itinerary"])

_ERRORS = {
    502: {"model": ErrorResponseSchema, "description": "AI returned an error/invalid itinerary"},
    503: {"model": ErrorResponseSchema, "description": "AI not configured, auth failed or over quota"},
    504: {"model": ErrorResponseSchema, "description": "AI request timed out"},
}


@router.post(
    "/generate",
    response_model=TripItineraryResponseSchema,
    responses=_ERRORS,
    summary="Generate a day-by-day itinerary",
)
async def generate_itinerary(
    trip: TripRequestSchema,
    engine: AIEngine = Depends(get_ai_engine),
    geocoder: GeocodingService = Depends(get_geocoding_service),
) -> TripItineraryResponseSchema:
    """Generate a day-by-day itinerary with Gemini and verify activity locations."""
    itinerary = await engine.generate_itinerary(trip)
    return await geocoder.verify_itinerary(itinerary)
