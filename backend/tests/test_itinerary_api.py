"""Integration & unit tests for POST /api/v1/itinerary/generate (OpenRouter)."""

import asyncio
import json

import httpx
import pytest

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


def _chat_response(content: str, status_code: int = 200) -> httpx.Response:
    return httpx.Response(
        status_code,
        json={"choices": [{"message": {"role": "assistant", "content": content}}]},
    )


def _make_fake_http(
    outcomes: list[object],
) -> tuple[httpx.AsyncClient, list[dict]]:
    queue = list(outcomes)
    calls: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(
            {
                "url": str(request.url),
                "body": json.loads(request.content),
                "headers": dict(request.headers),
            }
        )
        outcome = queue.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        if isinstance(outcome, httpx.Response):
            return outcome
        return _chat_response(str(outcome))

    return httpx.AsyncClient(transport=httpx.MockTransport(handler)), calls


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
    fake_http, calls = _make_fake_http([VALID_LLM_JSON])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=1)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

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

    # Sequential server-assigned activity IDs, coordinates null until geocoding.
    act_ids = [a.activity_id for d in parsed.days for a in d.activities]
    assert act_ids == ["act_01", "act_02", "act_03", "act_04"]
    assert all(
        a.verified is False and a.latitude is None
        for d in parsed.days
        for a in d.activities
    )

    # Confirm OpenRouter was called with structured JSON schema response_format.
    assert len(calls) == 1
    assert calls[0]["body"]["model"] == settings.openrouter_model
    assert calls[0]["body"]["response_format"]["type"] == "json_schema"


async def test_generate_itinerary_retries_on_malformed_json_then_succeeds(client):
    fake_http, calls = _make_fake_http(["not valid json {{{", VALID_LLM_JSON])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=1)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 200
    assert len(calls) == 2


# --- Error handling --------------------------------------------------------


async def test_generate_itinerary_fails_when_api_key_missing(client):
    settings = Settings(openrouter_api_key=None)
    _override_engine(AIEngine(settings=settings, http_client=None))

    response = await client.post("/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD)

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_NOT_CONFIGURED"


async def test_generate_itinerary_handles_malformed_json_after_retries(client):
    fake_http, calls = _make_fake_http(["{bad", "{still bad"])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=1)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_INVALID_RESPONSE"
    assert len(calls) == 2


async def test_generate_itinerary_handles_empty_llm_text(client):
    fake_http, _ = _make_fake_http([""])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

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
    fake_http, _ = _make_fake_http([one_day_only])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

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
    fake_http, _ = _make_fake_http([exc])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 504
    assert response.json()["error"]["code"] == "AI_TIMEOUT"


@pytest.mark.parametrize("code", [401, 403])
async def test_generate_itinerary_handles_invalid_api_key(client, code):
    fake_http, _ = _make_fake_http(
        [httpx.Response(code, json={"error": {"message": "Unauthorized"}})]
    )
    settings = Settings(openrouter_api_key="bad-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_AUTH_FAILED"


@pytest.mark.parametrize("code", [402, 429])
async def test_generate_itinerary_handles_ai_rate_limit(client, code):
    fake_http, _ = _make_fake_http(
        [httpx.Response(code, json={"error": {"message": "Quota exceeded"}})]
    )
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_RATE_LIMITED"


@pytest.mark.parametrize(
    "outcome",
    [
        httpx.Response(500, json={"error": {"message": "Internal"}}),
        httpx.Response(503, json={"error": {"message": "Unavailable"}}),
        httpx.ConnectError("connection refused"),
    ],
)
async def test_generate_itinerary_handles_provider_errors(client, outcome):
    fake_http, _ = _make_fake_http([outcome])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        response = await client.post(
            "/api/v1/itinerary/generate", json=VALID_TRIP_PAYLOAD
        )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_PROVIDER_ERROR"


async def test_generate_itinerary_rejects_invalid_request_body(client):
    bad_payload = {**VALID_TRIP_PAYLOAD, "end_date": "2026-06-01"}
    response = await client.post("/api/v1/itinerary/generate", json=bad_payload)
    assert response.status_code == 422
