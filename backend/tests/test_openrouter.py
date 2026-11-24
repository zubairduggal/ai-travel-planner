"""Tests for the optional OpenRouter AI provider (mocked + opt-in live test)."""

import json
import os
import time

import httpx
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.main import app
from app.models.response_schemas import TripItineraryResponseSchema
from app.services.ai_engine import AIEngine, get_ai_engine

pytestmark = pytest.mark.anyio

TRIP_PAYLOAD = {
    "destination": "Hunza Valley, Pakistan",
    "start_date": "2026-06-10",
    "end_date": "2026-06-11",
    "budget": 300.0,
    "currency": "USD",
    "interests": ["Nature", "History"],
    "travel_style": "Moderate",
}

VALID_OPENROUTER_ITINERARY_JSON = json.dumps(
    {
        "days": [
            {
                "day_number": 2,
                "title": "Attabad Lake Excursion",
                "activities": [
                    {
                        "time_slot": "Morning",
                        "title": "Boat ride at Attabad Lake",
                        "description": "Cruise across the turquoise glacial lake.",
                        "category": "Nature",
                        "estimated_cost": 30.0,
                    }
                ],
            },
            {
                "day_number": 1,
                "title": "Karimabad Heritage",
                "activities": [
                    {
                        "time_slot": "Morning",
                        "title": "Visit Baltit Fort",
                        "description": "Tour the historic hilltop fort.",
                        "category": "Historical",
                        "estimated_cost": 15.0,
                    }
                ],
            },
        ]
    }
)

VALID_SLOT_JSON = json.dumps(
    {
        "time_slot": "Evening",
        "title": "Sunset at Eagle's Nest",
        "description": "Golden hour panorama over Hunza Valley.",
        "category": "Nature",
        "estimated_cost": 10.0,
    }
)


def _chat_completion_body(content: str) -> dict:
    return {"choices": [{"message": {"role": "assistant", "content": content}}]}


def _openrouter_settings(**overrides) -> Settings:
    defaults = {
        "openrouter_api_key": "test-openrouter-secret-value",
        "openrouter_model": "nvidia/nemotron-3.5-super-vl:free",
        "openrouter_max_retries": 1,
    }
    defaults.update(overrides)
    return Settings(**defaults)


async def test_openrouter_generate_itinerary_success_and_request_shape(client):
    captured: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        captured.append(request)
        return httpx.Response(
            200,
            json=_chat_completion_body(VALID_OPENROUTER_ITINERARY_JSON),
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        engine = AIEngine(settings=_openrouter_settings(), http_client=http)
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)

    assert res.status_code == 200
    body = res.json()
    assert body["trip_id"].startswith("itinerary_")
    assert body["total_estimated_cost"] == 45.0
    assert [d["day_number"] for d in body["days"]] == [1, 2]
    assert body["days"][0]["activities"][0]["activity_id"] == "act_01"

    assert len(captured) == 1
    req = captured[0]
    assert str(req.url) == "https://openrouter.ai/api/v1/chat/completions"
    assert req.headers["Authorization"] == "Bearer test-openrouter-secret-value"
    sent = json.loads(req.content)
    assert sent["model"] == "nvidia/nemotron-3.5-super-vl:free"
    assert sent["response_format"]["type"] == "json_schema"
    assert sent["response_format"]["json_schema"]["strict"] is True
    assert "<user_request_data>" in sent["messages"][1]["content"]


async def test_openrouter_regenerate_slot_success(client):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_chat_completion_body(VALID_SLOT_JSON))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        engine = AIEngine(settings=_openrouter_settings(), http_client=http)
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res = await client.post(
            "/api/v1/itinerary/regenerate-slot",
            json={
                "destination": "Hunza Valley, Pakistan",
                "day_number": 1,
                "time_slot": "Evening",
                "budget_remaining": 40.0,
                "currency": "USD",
                "interests": ["Nature"],
                "travel_style": "Moderate",
                "activity_id": "act_03",
            },
        )

    assert res.status_code == 200
    assert res.json()["activity_id"] == "act_03"
    assert res.json()["title"] == "Sunset at Eagle's Nest"


async def test_openrouter_retries_malformed_json_then_succeeds(client):
    replies = [
        httpx.Response(200, json=_chat_completion_body("{not valid json")),
        httpx.Response(
            200,
            json=_chat_completion_body(
                f"```json\n{VALID_OPENROUTER_ITINERARY_JSON}\n```"
            ),
        ),
    ]
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return replies.pop(0)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        engine = AIEngine(settings=_openrouter_settings(), http_client=http)
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)

    assert res.status_code == 200
    assert calls == 2


async def test_openrouter_exhausted_malformed_json_and_empty_content(client):
    def bad_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_chat_completion_body("{broken"))

    async with httpx.AsyncClient(transport=httpx.MockTransport(bad_handler)) as http:
        engine = AIEngine(
            settings=_openrouter_settings(openrouter_max_retries=1), http_client=http
        )
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res.status_code == 502
    assert res.json()["error"]["code"] == "AI_INVALID_RESPONSE"

    def empty_handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_chat_completion_body(""))

    async with httpx.AsyncClient(transport=httpx.MockTransport(empty_handler)) as http:
        engine = AIEngine(
            settings=_openrouter_settings(openrouter_max_retries=0), http_client=http
        )
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res_empty = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res_empty.status_code == 502
    assert res_empty.json()["error"]["code"] == "AI_INVALID_RESPONSE"


@pytest.mark.parametrize(
    ("upstream_status", "expected_status", "expected_code"),
    [
        (401, 503, "AI_AUTH_FAILED"),
        (402, 503, "AI_RATE_LIMITED"),
        (429, 503, "AI_RATE_LIMITED"),
        (500, 502, "AI_PROVIDER_ERROR"),
        (503, 502, "AI_PROVIDER_ERROR"),
    ],
)
async def test_openrouter_http_error_mapping_and_no_secret_in_logs(
    client, caplog, upstream_status, expected_status, expected_code
):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(upstream_status, json={"error": {"message": "fail"}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        engine = AIEngine(
            settings=_openrouter_settings(openrouter_max_retries=0), http_client=http
        )
        app.dependency_overrides[get_ai_engine] = lambda: engine
        with caplog.at_level("WARNING"):
            res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)

    assert res.status_code == expected_status
    assert res.json()["error"]["code"] == expected_code
    assert "test-openrouter-secret-value" not in caplog.text
    assert "Authorization" not in caplog.text


async def test_openrouter_timeout_and_network_errors(client):
    def timeout_handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow")

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(timeout_handler)
    ) as http:
        engine = AIEngine(
            settings=_openrouter_settings(openrouter_max_retries=0), http_client=http
        )
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res.status_code == 504
    assert res.json()["error"]["code"] == "AI_TIMEOUT"

    def net_handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refused")

    async with httpx.AsyncClient(transport=httpx.MockTransport(net_handler)) as http:
        engine = AIEngine(
            settings=_openrouter_settings(openrouter_max_retries=0), http_client=http
        )
        app.dependency_overrides[get_ai_engine] = lambda: engine
        res_net = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res_net.status_code == 502
    assert res_net.json()["error"]["code"] == "AI_PROVIDER_ERROR"


async def test_openrouter_missing_key_and_https_url_validation(client):
    engine = AIEngine(settings=Settings(openrouter_api_key=None))
    app.dependency_overrides[get_ai_engine] = lambda: engine
    res = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    assert res.status_code == 503
    assert res.json()["error"]["code"] == "AI_NOT_CONFIGURED"

    with pytest.raises(ValidationError):
        Settings(openrouter_base_url="http://insecure.example.com/v1")


# --- Optional live OpenRouter integration test ------------------------------


@pytest.mark.live
@pytest.mark.skipif(
    os.getenv("RUN_LIVE_TESTS") != "1" or not os.getenv("OPENROUTER_API_KEY"),
    reason="Set RUN_LIVE_TESTS=1 and OPENROUTER_API_KEY to run live OpenRouter tests.",
)
async def test_generate_itinerary_live_openrouter(client):
    live_settings = Settings()
    app.dependency_overrides[get_ai_engine] = lambda: AIEngine(settings=live_settings)

    started = time.perf_counter()
    response = await client.post("/api/v1/itinerary/generate", json=TRIP_PAYLOAD)
    elapsed = time.perf_counter() - started
    print(
        f"OPENROUTER_LIVE model={live_settings.openrouter_model} "
        f"status={response.status_code} latency_s={elapsed:.2f}"
    )

    assert response.status_code == 200
    parsed = TripItineraryResponseSchema(**response.json())
    assert parsed.duration_days == 2
