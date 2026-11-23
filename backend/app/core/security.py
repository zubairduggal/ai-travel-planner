"""Rate limiting (SlowAPI) & API key authentication (M4)."""

import secrets

from fastapi import Depends, Header, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import Settings, get_settings
from app.core.exceptions import UnauthorizedError


def get_client_identifier(request: Request) -> str:
    """Identify the caller by X-User-Id, X-Forwarded-For, or client IP."""
    user_id = request.headers.get("X-User-Id")
    if user_id and user_id.strip():
        return f"user:{user_id.strip()}"

    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        first_ip = forwarded.split(",")[0].strip()
        if first_ip:
            return first_ip

    return get_remote_address(request)


def _itinerary_rate_limit() -> str:
    return get_settings().rate_limit_itinerary


def _regenerate_slot_rate_limit() -> str:
    return get_settings().rate_limit_regenerate_slot


limiter = Limiter(
    key_func=get_client_identifier,
    storage_uri=get_settings().rate_limit_storage_uri,
    in_memory_fallback_enabled=True,
)


def reset_rate_limiter() -> None:
    """Reset in-memory/configured rate limit counters (useful in tests)."""
    limiter.reset()


async def rate_limit_exceeded_handler(
    request: Request, exc: RateLimitExceeded
) -> JSONResponse:
    """Return standardized JSON error envelope with HTTP 429."""
    detail = getattr(exc, "detail", str(exc))
    return JSONResponse(
        status_code=429,
        content={
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": f"Rate limit exceeded: {detail}",
            }
        },
    )


async def verify_api_key(
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
    settings: Settings = Depends(get_settings),
) -> None:
    """Enforce X-API-Key authentication whenever API_KEY is configured."""
    expected = settings.api_key
    if not expected:
        return
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise UnauthorizedError()
