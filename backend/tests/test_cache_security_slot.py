"""Tests for caching, rate limiting (5/day), API key auth, and regenerate-slot (M4)."""

import json
import time
from types import SimpleNamespace

import httpx
import pytest

from app.core.config import Settings, get_settings
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
from app.services.geocoding_service import GeocodingService, get_geocoding_service

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

SLOT_LLM_JSON = json.dumps(
    {
        "time_slot": "Afternoon",
        "title": "Explore Altit Fort & Royal Garden",
        "description": "Walk through the 11th-century fort and apricot orchards.",
        "category": "Historical",
        "estimated_cost": 12.0,
    }
)


class _CountingModels:
    def __init__(self, responses: list[str]) -> None:
        self._responses = list(responses)
        self.call_count = 0
        self.last_prompt: str | None = None

    async def generate_content(self, *, model, contents, config):
        self.call_count += 1
        self.last_prompt = contents
        text = (
            self._responses.pop(0) if len(self._responses) > 1 else self._responses[0]
        )
        return SimpleNamespace(text=text)


def _install_fake_ai(responses: list[str], *, max_retries: int = 1) -> _CountingModels:
    models = _CountingModels(responses)
    fake_client = SimpleNamespace(aio=SimpleNamespace(models=models))
    engine = AIEngine(
        settings=Settings(gemini_api_key="test-key", gemini_max_retries=max_retries),
        client=fake_client,
    )
    app.dependency_overrides[get_ai_engine] = lambda: engine
    return models


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
        # 1st call -> MISS (invokes Gemini once)
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
    finally:
        await disk_cache.close()


# --- Rate limiting (5 requests/day -> 6th returns 429) ---------------------


async def test_rate_limit_enforces_5_per_day_and_blocks_header_spoofing(client):
    _install_fake_ai([ONE_DAY_LLM_JSON])

    # First 5 requests succeed.
    for i in range(5):
        res = await client.post(
            "/api/v1/itinerary/generate",
            json={**TRIP_PAYLOAD, "budget": 200.0 + i},
        )
        assert res.status_code == 200, f"Request {i + 1} should succeed"

    # 6th request breaches the 5/day limit -> 429 Too Many Requests.
    blocked = await client.post(
        "/api/v1/itinerary/generate",
        json={**TRIP_PAYLOAD, "budget": 999.0},
    )
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "RATE_LIMIT_EXCEEDED"
    assert blocked.headers["Cache-Control"] == "no-store"

    # Spoofing X-User-Id or X-Forwarded-For must NOT bypass the limit by default.
    spoof_user = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-User-Id": "attacker_bypass_99"},
    )
    assert spoof_user.status_code == 429

    spoof_ip = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-Forwarded-For": "198.51.100.77"},
    )
    assert spoof_ip.status_code == 429


async def test_trusted_proxy_headers_validate_ip_address(client, monkeypatch):
    from app.core import security

    monkeypatch.setattr(
        security,
        "get_settings",
        lambda: Settings(trust_proxy_headers=True),
    )
    _install_fake_ai([ONE_DAY_LLM_JSON])

    # Exhaust IP 203.0.113.10
    for i in range(5):
        res = await client.post(
            "/api/v1/itinerary/generate",
            json={**TRIP_PAYLOAD, "budget": 200.0 + i},
            headers={"X-Forwarded-For": "203.0.113.10, 10.0.0.1"},
        )
        assert res.status_code == 200

    blocked = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-Forwarded-For": "203.0.113.10"},
    )
    assert blocked.status_code == 429

    # Different valid client IP behind proxy is isolated.
    other_ip = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-Forwarded-For": "198.51.100.42"},
    )
    assert other_ip.status_code == 200


async def test_security_headers_and_dos_input_bounds(client):
    from pydantic import ValidationError
    from app.api.v1.endpoints.weather import get_weather_http_client

    health = await client.get("/api/v1/health")
    assert health.headers["X-Content-Type-Options"] == "nosniff"
    assert health.headers["X-Frame-Options"] == "DENY"
    assert health.headers["Referrer-Policy"] == "no-referrer"

    # Trip > 14 days rejected (prevents LLM & Nominatim DoS).
    too_long = await client.post(
        "/api/v1/itinerary/generate",
        json={**TRIP_PAYLOAD, "start_date": "2026-06-01", "end_date": "2026-07-01"},
    )
    assert too_long.status_code == 422

    # Excessively huge budget rejected.
    huge_budget = await client.post(
        "/api/v1/itinerary/generate",
        json={**TRIP_PAYLOAD, "budget": 9_999_999.0},
    )
    assert huge_budget.status_code == 422

    # Plaintext HTTP upstream URLs rejected in Settings.
    with pytest.raises(ValidationError):
        Settings(nominatim_base_url="http://evil.example.com")

    # Malformed weather JSON payload returns clean 502, never unhandled 500.
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(200, json=["bad"]))
    ) as http:
        app.dependency_overrides[get_weather_http_client] = lambda: http
        res_bad = await client.get(
            "/api/v1/weather", params={"lat": 36.32, "lon": 74.67}
        )
    assert res_bad.status_code == 502
    assert res_bad.json()["error"]["code"] == "EXTERNAL_SERVICE_ERROR"


async def test_geocoding_lru_cache_is_bounded():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=[{"lat": "36.32", "lon": "74.66", "display_name": "Place"}],
        )

    settings = Settings(
        nominatim_min_interval_seconds=0.0,
        geocoding_cache_max_entries=10,
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        svc = GeocodingService(settings=settings, http_client=http)
        for i in range(15):
            await svc.geocode_place(f"Unique Place {i}")
        assert len(svc._cache) == 10


# --- API key authentication (X-API-Key) ------------------------------------


async def test_api_key_auth_protects_itinerary_routes_but_keeps_health_public(client):
    protected_settings = Settings(
        app_env="production",
        api_key="super-secret-flutter-key",
        nominatim_min_interval_seconds=0.0,
    )
    app.dependency_overrides[get_settings] = lambda: protected_settings
    _install_fake_ai([ONE_DAY_LLM_JSON])

    # Health check stays public.
    assert (await client.get("/api/v1/health")).status_code == 200

    # Missing key -> 401
    res_missing = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res_missing.status_code == 401
    assert res_missing.json()["error"]["code"] == "UNAUTHORIZED"

    # Wrong key -> 401
    res_wrong = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-API-Key": "wrong-key"},
    )
    assert res_wrong.status_code == 401

    # Valid key -> 200
    res_ok = await client.post(
        "/api/v1/itinerary/generate",
        json=TRIP_PAYLOAD,
        headers={"X-API-Key": "super-secret-flutter-key"},
    )
    assert res_ok.status_code == 200


# --- Single-slot regeneration (POST /api/v1/itinerary/regenerate-slot) -----


async def test_regenerate_slot_success_with_geocoding(client):
    models = _install_fake_ai([SLOT_LLM_JSON])

    def geo_handler(request: httpx.Request) -> httpx.Response:
        q = request.url.params.get("q", "").lower()
        if "altit" in q:
            return httpx.Response(
                200,
                json=[
                    {"lat": "36.3144", "lon": "74.6819", "display_name": "Altit Fort"}
                ],
            )
        return httpx.Response(200, json=[])

    async with httpx.AsyncClient(transport=httpx.MockTransport(geo_handler)) as http:
        app.dependency_overrides[get_geocoding_service] = lambda: GeocodingService(
            settings=Settings(nominatim_min_interval_seconds=0.0),
            http_client=http,
        )
        res = await client.post(
            "/api/v1/itinerary/regenerate-slot",
            json={
                "destination": "Hunza Valley, Pakistan",
                "day_number": 1,
                "time_slot": "Afternoon",
                "budget_remaining": 40.0,
                "currency": "usd",
                "interests": ["History", "Photography"],
                "travel_style": "Moderate",
                "existing_activity_titles": ["Visit Baltit Fort"],
                "activity_id": "act_02",
                "user_note": "Something historic nearby",
            },
        )

    assert res.status_code == 200
    body = res.json()
    assert body["activity_id"] == "act_02"
    assert body["time_slot"] == "Afternoon"
    assert "Altit Fort" in body["title"]
    assert body["verified"] is True
    assert body["latitude"] == 36.3144
    assert body["longitude"] == 74.6819
    assert models.last_prompt is not None
    assert "Visit Baltit Fort" in models.last_prompt


async def test_regenerate_slot_retries_malformed_json_and_handles_errors(client):
    # Retries once then succeeds, generating an activity_id when omitted.
    models = _install_fake_ai(["bad json", SLOT_LLM_JSON], max_retries=1)
    payload = {
        "destination": "Hunza Valley, Pakistan",
        "day_number": 2,
        "time_slot": "Evening",
        "budget_remaining": 25.0,
        "currency": "USD",
        "interests": ["Local Food"],
        "travel_style": "Budget",
    }
    res = await client.post("/api/v1/itinerary/regenerate-slot", json=payload)
    assert res.status_code == 200
    assert res.json()["activity_id"].startswith("act_")
    assert res.json()["time_slot"] == "Evening"
    assert models.call_count == 2

    # Exhausted retries -> 502
    _install_fake_ai(["{bad", "{still bad"], max_retries=1)
    res_bad = await client.post("/api/v1/itinerary/regenerate-slot", json=payload)
    assert res_bad.status_code == 502
    assert res_bad.json()["error"]["code"] == "AI_INVALID_RESPONSE"

    # Unconfigured Gemini -> 503
    app.dependency_overrides[get_ai_engine] = lambda: AIEngine(
        settings=Settings(gemini_api_key=None), client=None
    )
    res_unconf = await client.post("/api/v1/itinerary/regenerate-slot", json=payload)
    assert res_unconf.status_code == 503
    assert res_unconf.json()["error"]["code"] == "AI_NOT_CONFIGURED"

    # Invalid request payload -> 422
    res_422 = await client.post(
        "/api/v1/itinerary/regenerate-slot",
        json={**payload, "currency": "12$", "interests": ["  "]},
    )
    assert res_422.status_code == 422
