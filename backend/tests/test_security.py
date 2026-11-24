"""Tests for rate limiting, proxy validation, security headers, and API key auth."""

import json

import httpx
import pytest

from app.core.config import Settings, get_settings
from app.main import app
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.geocoding_service import GeocodingService

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


# --- Rate limiting (5 requests/day -> 6th returns 429) ---------------------


async def test_rate_limit_enforces_5_per_day_and_blocks_header_spoofing(
    client, monkeypatch
):
    from app.core import security

    monkeypatch.setattr(
        security,
        "get_settings",
        lambda: Settings(_env_file=None, rate_limit_itinerary="5/day"),
    )
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
        lambda: Settings(
            _env_file=None,
            trust_proxy_headers=True,
            rate_limit_itinerary="5/day",
        ),
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
