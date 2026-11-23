"""Integration & unit tests for POST /api/v1/itinerary/generate (M2)."""

import asyncio
import json
import os
from types import SimpleNamespace

import httpx
import pytest
from google.genai import errors as genai_errors

from app.core.config import Settings
from app.main import app
from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import TripItineraryResponseSchema
from app.services.ai_engine import AIEngine, get_ai_engine
from app.utils.prompt_templates import build_itinerary_prompt

pytestmark = pytest.mark.anyio

VALID_TRIP_PAYLOAD = {
    "destination": "Hunza Valley, Pakistan",
    "start_date": "2026-06-10",
    "end_date": "2026-06-11",
    "budget": 300.0,
    "currency": "USD",
    "interests": ["Nature", "Photography", "Local Food"],
    "travel_style": "Moderate",
}

VALID_LLM_JSON = json.dumps(
    {
        "days": [
            {
                "day_number": 2,
                "title": "Attabad Lake & Passu Cones",
                "activities": [
                    {
                        "time_slot": "Morning",
                        "title": "Boat ride at Attabad Lake",
                        "description": (
                            "Enjoy turquoise waters framed by steep Karakoram peaks."
                        ),
                        "category": "Nature",
                        "estimated_cost": 35.5,
                    },
                    {
                        "time_slot": "Afternoon",
                        "title": "Walk Hussaini Suspension Bridge",
                        "description": (
                            "Cross the iconic cable bridge near Passu village."
                        ),
                        "category": "Adventure",
                        "estimated_cost": 10.0,
                    },
                ],
            },
            {
                "day_number": 1,
                "title": "Arrival & Karimabad Exploration",
                "activities": [
                    {
                        "time_slot": "Morning",
                        "title": "Visit Baltit Fort",
                        "description": (
                            "Explore the 700-year-old historic fort overlooking "
                            "the valley."
                        ),
                        "category": "Historical",
                        "estimated_cost": 15.0,
                    },
                    {
                        "time_slot": "Evening",
                        "title": "Sunset at Eagle's Nest Viewpoint",
                        "description": (
                            "Watch golden hour over Rakaposhi and Ultar Sar."
                        ),
                        "category": "Photography",
                        "estimated_cost": 20.0,
                    },
                ],
            },
        ]
    }
)


class _FakeAsyncModels:
    """Scriptable fake for `client.aio.models`."""

    def __init__(self, outcomes: list[object]) -> None:
        self._outcomes = list(outcomes)
        self.calls: list[dict] = []

    async def generate_content(self, *, model, contents, config):
        self.calls.append({"model": model, "contents": contents, "config": config})
        outcome = self._outcomes.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return SimpleNamespace(text=outcome)


def _make_fake_client(
    outcomes: list[object],
) -> tuple[SimpleNamespace, _FakeAsyncModels]:
    models = _FakeAsyncModels(outcomes)
    client = SimpleNamespace(aio=SimpleNamespace(models=models))
    return client, models


def _override_engine(engine: AIEngine) -> None:
    app.dependency_overrides[get_ai_engine] = lambda: engine


# --- Prompt builder --------------------------------------------------------


def test_prompt_includes_all_trip_parameters():
    trip = TripRequestSchema(**VALID_TRIP_PAYLOAD)
    prompt = build_itinerary_prompt(trip)

    assert "Hunza Valley, Pakistan" in prompt
    assert "2026-06-10" in prompt
    assert "2026-06-11" in prompt
    assert "2" in prompt
    assert "300 USD" in prompt
    assert "Nature, Photography, Local Food" in prompt
    assert "Moderate" in prompt


# --- Happy path & retry ----------------------------------------------------


async def test_generate_itinerary_success(client):
    fake_client, models = _make_fake_client([VALID_LLM_JSON])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=1)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 200
    body = response.json()
    parsed = TripItineraryResponseSchema(**body)

    assert parsed.trip_id.startswith("itinerary_")
    assert len(parsed.trip_id) == len("itinerary_") + 8
    assert parsed.destination == "Hunza Valley, Pakistan"
    assert parsed.duration_days == 2
    assert parsed.currency == "USD"
    # Days must be sorted 1 -> 2 even when the LLM returned day 2 first.
    assert [d.day_number for d in parsed.days] == [1, 2]
    assert parsed.total_estimated_cost == 80.5

    # Sequential server-assigned activity IDs, coordinates null until M3.
    act_ids = [a.activity_id for d in parsed.days for a in d.activities]
    assert act_ids == ["act_01", "act_02", "act_03", "act_04"]
    assert all(
        a.verified is False and a.latitude is None
        for d in parsed.days
        for a in d.activities
    )

    # Confirm Gemini was called with structured JSON output config.
    assert len(models.calls) == 1
    assert models.calls[0]["model"] == settings.gemini_model
    assert models.calls[0]["config"].response_mime_type == "application/json"


async def test_generate_itinerary_retries_on_malformed_json_then_succeeds(client):
    fake_client, models = _make_fake_client(["not valid json {{{", VALID_LLM_JSON])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=1)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 200
    assert len(models.calls) == 2


# --- Error handling --------------------------------------------------------


async def test_generate_itinerary_fails_when_api_key_missing(client):
    settings = Settings(gemini_api_key=None)
    _override_engine(AIEngine(settings=settings, client=None))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_NOT_CONFIGURED"


async def test_generate_itinerary_handles_malformed_json_after_retries(client):
    fake_client, models = _make_fake_client(["{bad", "{still bad"])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=1)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_INVALID_RESPONSE"
    assert len(models.calls) == 2


async def test_generate_itinerary_handles_empty_llm_text(client):
    fake_client, _ = _make_fake_client([""])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_INVALID_RESPONSE"


async def test_generate_itinerary_rejects_wrong_day_count(client):
    one_day_only = json.dumps(
        {
            "days": [
                {
                    "day_number": 1,
                    "title": "Only One Day",
                    "activities": [
                        {
                            "time_slot": "Morning",
                            "title": "Visit Baltit Fort",
                            "description": "Historic fort.",
                            "category": "Historical",
                            "estimated_cost": 15.0,
                        }
                    ],
                }
            ]
        }
    )
    fake_client, _ = _make_fake_client([one_day_only])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_INVALID_RESPONSE"


@pytest.mark.parametrize(
    "exc",
    [
        asyncio.TimeoutError(),
        httpx.ReadTimeout("timed out"),
    ],
)
async def test_generate_itinerary_handles_timeout(client, exc):
    fake_client, _ = _make_fake_client([exc])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 504
    assert response.json()["error"]["code"] == "AI_TIMEOUT"


@pytest.mark.parametrize(
    ("code", "payload"),
    [
        (400, {"error": {"code": 400, "message": "API_KEY_INVALID"}}),
        (401, {"error": {"code": 401, "message": "Unauthorized"}}),
        (403, {"error": {"code": 403, "message": "Forbidden"}}),
    ],
)
async def test_generate_itinerary_handles_invalid_api_key(client, code, payload):
    api_error = genai_errors.ClientError(code, payload)
    fake_client, _ = _make_fake_client([api_error])
    settings = Settings(gemini_api_key="bad-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_AUTH_FAILED"


async def test_generate_itinerary_handles_gemini_rate_limit(client):
    api_error = genai_errors.ClientError(
        429, {"error": {"code": 429, "message": "RESOURCE_EXHAUSTED"}}
    )
    fake_client, _ = _make_fake_client([api_error])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_RATE_LIMITED"


@pytest.mark.parametrize(
    "exc",
    [
        genai_errors.ServerError(500, {"error": {"code": 500, "message": "Internal"}}),
        httpx.ConnectError("connection refused"),
    ],
)
async def test_generate_itinerary_handles_provider_errors(client, exc):
    fake_client, _ = _make_fake_client([exc])
    settings = Settings(gemini_api_key="test-key", gemini_max_retries=0)
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_PROVIDER_ERROR"


async def test_generate_itinerary_falls_back_on_503_unavailable(client):
    unavailable = genai_errors.ServerError(
        503, {"error": {"code": 503, "message": "UNAVAILABLE"}}
    )
    fake_client, models = _make_fake_client([unavailable, VALID_LLM_JSON])
    settings = Settings(
        gemini_api_key="test-key",
        gemini_model="gemini-3.8-flash",
        gemini_fallback_model="gemini-3.5-flash-lite",
        gemini_max_retries=0,
    )
    _override_engine(AIEngine(settings=settings, client=fake_client))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 200
    assert [c["model"] for c in models.calls] == [
        "gemini-3.8-flash",
        "gemini-3.5-flash-lite",
    ]


async def test_generate_itinerary_rejects_invalid_request_body(client):
    bad_payload = {**VALID_TRIP_PAYLOAD, "end_date": "2026-06-01"}
    response = await client.post("/api/v1/itinerary/generate", json=bad_payload)
    assert response.status_code == 422


# --- Optional live Gemini integration test ---------------------------------


@pytest.mark.live
@pytest.mark.skipif(
    os.getenv("RUN_LIVE_TESTS") != "1" or not os.getenv("GEMINI_API_KEY"),
    reason="Set RUN_LIVE_TESTS=1 and GEMINI_API_KEY to run live Gemini tests.",
)
async def test_generate_itinerary_live_gemini(client):
    live_settings = Settings()
    _override_engine(AIEngine(settings=live_settings))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 200
    parsed = TripItineraryResponseSchema(**response.json())
    assert parsed.duration_days == 2
    assert len(parsed.days) == 2
    assert all(len(day.activities) >= 1 for day in parsed.days)
