"""Main API v1 router."""

from fastapi import APIRouter

from app.api.v1.endpoints import health, itinerary

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(itinerary.router)
