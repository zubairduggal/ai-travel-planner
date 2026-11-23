"""Pytest fixtures & mock client setup."""

from collections.abc import AsyncIterator

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import reset_rate_limiter
from app.main import app
from app.services.cache_service import (
    CacheService,
    MemoryCacheBackend,
    get_cache_service,
)
from app.services.geocoding_service import GeocodingService, get_geocoding_service


@pytest.fixture
def anyio_backend() -> str:
    # Run async tests on asyncio via the anyio pytest plugin bundled with FastAPI.
    return "asyncio"


@pytest.fixture
def test_settings() -> Settings:
    return Settings(
        app_env="development",
        debug=True,
        nominatim_min_interval_seconds=0.0,
        cache_backend="memory",
        api_key=None,
    )


@pytest.fixture
def noop_geocoder(test_settings: Settings) -> GeocodingService:
    """Default offline geocoder returning no hits so unit tests never hit the network."""
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json=[]))
    http_client = httpx.AsyncClient(transport=transport)
    return GeocodingService(settings=test_settings, http_client=http_client)


@pytest.fixture
def memory_cache() -> CacheService:
    """Isolated fresh in-memory cache per test."""
    return CacheService(backend=MemoryCacheBackend(), ttl_seconds=3600)


@pytest.fixture
async def client(
    test_settings: Settings,
    noop_geocoder: GeocodingService,
    memory_cache: CacheService,
) -> AsyncIterator[AsyncClient]:
    reset_rate_limiter()
    app.dependency_overrides[get_settings] = lambda: test_settings
    app.dependency_overrides[get_geocoding_service] = lambda: noop_geocoder
    app.dependency_overrides[get_cache_service] = lambda: memory_cache
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as async_client:
        yield async_client
    app.dependency_overrides.clear()
    reset_rate_limiter()
