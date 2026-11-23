"""Server health check endpoint."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.models.response_schemas import HealthResponseSchema

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponseSchema)
async def health_check(
    settings: Settings = Depends(get_settings),
) -> HealthResponseSchema:
    """Return server status, current UTC timestamp, and environment."""
    return HealthResponseSchema(
        status="ok",
        timestamp=datetime.now(timezone.utc),
        environment=settings.app_env,
    )
