"""Rate limiting (SlowAPI) & API key authentication (M4)."""

import ipaddress
import secrets

from fastapi import Depends, Header, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import Settings, get_settings
from app.core.exceptions import UnauthorizedError


def get_client_identifier(request: Request) -> str:
    """Identify the caller by client IP (or trusted X-Forwarded-For IP).

    Client-supplied headers like X-User-Id are never trusted for rate limiting
    because any attacker could rotate them to bypass daily limits.
    X-Forwarded-For is only consulted when `TRUST_PROXY_HEADERS=true` and is
    validated as a real IP address.
    """
    settings = get_settings()
    if settings.trust_proxy_headers:
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            candidate = forwarded.split(",")[0].strip()
            try:
                return str(ipaddress.ip_address(candidate))
            except ValueError:
                pass

    return get_remote_address(request)


def _itinerary_rate_limit() -> str:
    return get_settings().rate_limit_itinerary


def _regenerate_slot_rate_limit() -> str:
    return get_settings().rate_limit_regenerate_slot


def _weather_rate_limit() -> str:
    return get_settings().rate_limit_weather


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
        headers={"Cache-Control": "no-store"},
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
