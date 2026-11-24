"""Tests for single-slot regeneration (POST /api/v1/itinerary/regenerate-slot)."""

import json

import httpx
import pytest

from app.core.config import Settings
from app.main import app
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.geocoding_service import GeocodingService, get_geocoding_service

pytestmark = pytest.mark.anyio

SLOT_LLM_JSON = json.dumps(
    {
        "time_slot": "Afternoon",
        "title": "Explore Altit Fort & Royal Garden",
        "description": "Walk through the 11th-century fort and apricot orchards.",
        "category": "Historical",
        "estimated_cost": 12.0,
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

    # Unconfigured OpenRouter -> 503
    app.dependency_overrides[get_ai_engine] = lambda: AIEngine(
        settings=Settings(openrouter_api_key=None), http_client=None
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
