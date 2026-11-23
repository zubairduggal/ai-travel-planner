"""Pytest fixtures & mock client setup."""

from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.main import app


@pytest.fixture
def anyio_backend() -> str:
    # Run async tests on asyncio via the anyio pytest plugin bundled with FastAPI.
    return "asyncio"


@pytest.fixture
def test_settings() -> Settings:
    return Settings(app_env="development", debug=True)


@pytest.fixture
async def client(test_settings: Settings) -> AsyncIterator[AsyncClient]:
    app.dependency_overrides[get_settings] = lambda: test_settings
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as async_client:
        yield async_client
    app.dependency_overrides.clear()
