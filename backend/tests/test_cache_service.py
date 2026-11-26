"""Tests for cache key normalization and DiskCache/Redis/Memory backends (M4)."""

import json
import time

import httpx
import pytest

from app.core.config import Settings
from app.main import app
from app.models.request_schemas import TripRequestSchema
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.cache_service import (
    CacheService,
    DiskCacheBackend,
    MemoryCacheBackend,
    RedisCacheBackend,
    build_itinerary_cache_key,
    get_cache_service,
)

pytestmark = pytest.mark.anyio

TRIP_PAYLOAD = {
    "destination": "Hunza Valley, Pakistan",
    "start_date": "2026-06-10",
    "end_date": "2026-06-10",
    "budget": 200.0,
    "currency": "USD",
    "interests": ["Nature", "Photography"],
    "travel_style": "Moderate",
}

ONE_DAY_LLM_JSON = json.dumps(
    {
        "days": [
            {
                "day_number": 1,
                "title": "Karimabad Highlights",
                "activities": [
                    {
                        "time_slot": "Morning",
                        "title": "Visit Baltit Fort",
                        "description": "Explore the historic hilltop fort.",
                        "category": "Historical",
                        "estimated_cost": 15.0,
                    }
                ],
            }
        ]
    }
)


class _CountingOpenRouter:
    def __init__(self, responses: list[str]) -> None:
        self._responses = list(responses)
        self.call_count = 0
        self.last_prompt: str | None = None

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.call_count += 1
        sent = json.loads(request.content)
        self.last_prompt = sent["messages"][1]["content"]
        text = (
            self._responses.pop(0) if len(self._responses) > 1 else self._responses[0]
        )
        return httpx.Response(
            200,
            json={"choices": [{"message": {"role": "assistant", "content": text}}]},
        )


def _install_fake_ai(
    responses: list[str], *, max_retries: int = 1
) -> _CountingOpenRouter:
    tracker = _CountingOpenRouter(responses)
    http_client = httpx.AsyncClient(transport=httpx.MockTransport(tracker.handler))
    engine = AIEngine(
        settings=Settings(
            openrouter_api_key="test-key", openrouter_max_retries=max_retries
        ),
        http_client=http_client,
    )
    app.dependency_overrides[get_ai_engine] = lambda: engine
    return tracker


# --- Cache key normalization & backends ------------------------------------


def test_cache_key_normalizes_whitespace_case_and_interest_order():
    t1 = TripRequestSchema(**TRIP_PAYLOAD)
    t2 = TripRequestSchema(
        **{
            **TRIP_PAYLOAD,
            "destination": "  hunza   valley, pakistan ",
            "currency": "usd",
            "interests": ["photography", "  NATURE  "],
            "travel_style": " moderate ",
        }
    )
    t3 = TripRequestSchema(**{**TRIP_PAYLOAD, "budget": 250.0})

    assert build_itinerary_cache_key(t1) == build_itinerary_cache_key(t2)
    assert build_itinerary_cache_key(t1) != build_itinerary_cache_key(t3)


def test_cache_key_separates_travel_mode_and_departure_city():
    air = TripRequestSchema(**TRIP_PAYLOAD, travel_mode="air")
    road = TripRequestSchema(**TRIP_PAYLOAD, travel_mode="road")
    train = TripRequestSchema(**TRIP_PAYLOAD, travel_mode="train")
    road_lhr = TripRequestSchema(
        **TRIP_PAYLOAD, travel_mode="road", departure_city="Lahore"
    )
    road_lhr_variant = TripRequestSchema(
        **TRIP_PAYLOAD, travel_mode="road", departure_city="  lahore  "
    )
    road_isb = TripRequestSchema(
        **TRIP_PAYLOAD, travel_mode="road", departure_city="Islamabad"
    )

    assert build_itinerary_cache_key(air) != build_itinerary_cache_key(road)
    assert build_itinerary_cache_key(road) != build_itinerary_cache_key(train)
    assert build_itinerary_cache_key(road) != build_itinerary_cache_key(road_lhr)
    assert build_itinerary_cache_key(road_lhr) == build_itinerary_cache_key(
        road_lhr_variant
    )
    assert build_itinerary_cache_key(road_lhr) != build_itinerary_cache_key(road_isb)


async def test_diskcache_backend_roundtrip_and_corrupted_entry(tmp_path):
    backend = DiskCacheBackend(str(tmp_path / "disk_test"))
    try:
        await backend.set("k1", "value-1", ttl_seconds=60)
        assert await backend.get("k1") == "value-1"

        await backend.delete("k1")
        assert await backend.get("k1") is None

        # Corrupted cached itinerary JSON is safely ignored and deleted.
        trip = TripRequestSchema(**TRIP_PAYLOAD)
        key = build_itinerary_cache_key(trip)
        await backend.set(key, "{not-valid-itinerary}", ttl_seconds=60)
        cache_svc = CacheService(backend=backend, ttl_seconds=60)
        assert await cache_svc.get_itinerary(trip) is None
        assert await backend.get(key) is None

        await backend.set("k2", "value-2", ttl_seconds=0)
        await backend.clear()
        assert await backend.get("k2") is None
    finally:
        await backend.close()


async def test_memory_backend_expiry():
    backend = MemoryCacheBackend()
    await backend.set("temp", "v", ttl_seconds=0)
    assert await backend.get("temp") == "v"
    await backend.delete("temp")
    assert await backend.get("temp") is None
    await backend.set("k", "v", ttl_seconds=60)
    await backend.clear()
    assert await backend.get("k") is None


async def test_redis_backend_operations_and_resilience():
    class _FakeRedis:
        def __init__(self, fail: bool = False) -> None:
            self.fail = fail
            self.data: dict[str, str] = {}
            self.closed = False

        async def get(self, key: str):
            if self.fail:
                raise ConnectionError("redis down")
            return self.data.get(key)

        async def set(self, key: str, value: str, ex: int | None = None):
            if self.fail:
                raise ConnectionError("redis down")
            self.data[key] = value

        async def delete(self, key: str):
            if self.fail:
                raise ConnectionError("redis down")
            self.data.pop(key, None)

        async def flushdb(self):
            if self.fail:
                raise ConnectionError("redis down")
            self.data.clear()

        async def aclose(self):
            if self.fail:
                raise ConnectionError("redis down")
            self.closed = True

    ok_redis = _FakeRedis()
    backend = RedisCacheBackend("redis://unused", client=ok_redis)
    await backend.set("a", "1", ttl_seconds=30)
    await backend.set("b", "2", ttl_seconds=0)
    assert await backend.get("a") == "1"
    await backend.delete("a")
    assert await backend.get("a") is None
    await backend.clear()
    assert await backend.get("b") is None
    await backend.close()
    assert ok_redis.closed is True

    # Failing Redis must degrade gracefully without raising.
    bad_backend = RedisCacheBackend("redis://unused", client=_FakeRedis(fail=True))
    await bad_backend.set("a", "1", ttl_seconds=30)
    assert await bad_backend.get("a") is None
    await bad_backend.delete("a")
    await bad_backend.clear()
    await bad_backend.close()


def test_cache_service_factory(tmp_path):
    svc_mem = CacheService.from_settings(Settings(cache_backend="memory"))
    assert isinstance(svc_mem._backend, MemoryCacheBackend)

    svc_disk = CacheService.from_settings(
        Settings(cache_backend="disk", diskcache_dir=str(tmp_path / "c"))
    )
    assert isinstance(svc_disk._backend, DiskCacheBackend)

    svc_redis = CacheService.from_settings(
        Settings(cache_backend="redis", redis_url="redis://localhost:6379/0")
    )
    assert isinstance(svc_redis._backend, RedisCacheBackend)


# --- Cache hit latency benchmark (< 50ms) with real DiskCache --------------


async def test_generate_itinerary_diskcache_hit_under_50ms(client, tmp_path):
    disk_cache = CacheService(
        backend=DiskCacheBackend(str(tmp_path / "bench")), ttl_seconds=3600
    )
    app.dependency_overrides[get_cache_service] = lambda: disk_cache
    models = _install_fake_ai([ONE_DAY_LLM_JSON])

    try:
        # 1st call -> MISS (invokes AI provider once)
        first = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
        assert first.status_code == 200
        assert first.headers["X-Cache"] == "MISS"
        assert models.call_count == 1

        # 2nd call with equivalent normalized parameters -> HIT (< 50ms, 0 new AI calls)
        variant_payload = {
            **TRIP_PAYLOAD,
            "destination": "  hunza valley, pakistan  ",
            "interests": ["Photography", "Nature"],
        }
        start = time.perf_counter()
        second = await client.post("/api/v1/itinerary/generate", json=variant_payload)
        elapsed_ms = (time.perf_counter() - start) * 1000

        assert second.status_code == 200
        assert second.headers["X-Cache"] == "HIT"
        assert second.json()["trip_id"] == first.json()["trip_id"]
        assert models.call_count == 1
        assert elapsed_ms < 50.0, f"Expected cache hit < 50ms, got {elapsed_ms:.2f}ms"

        # 3rd call with travel_mode='road' must NOT return the cached 'air' itinerary
        road_payload = {**TRIP_PAYLOAD, "travel_mode": "road"}
        third = await client.post("/api/v1/itinerary/generate", json=road_payload)
        assert third.status_code == 200
        assert third.headers["X-Cache"] == "MISS"
        assert models.call_count == 2
    finally:
        await disk_cache.close()
