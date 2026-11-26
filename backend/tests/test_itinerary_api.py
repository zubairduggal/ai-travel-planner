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
from app.services.poi_discovery_service import (
    DestinationPOIBundle,
    DiscoveredPOI,
    get_poi_discovery_service,
)
from app.services.pricing_service import (
    BasePricingProvider,
    PriceLookupResult,
    PricingService,
    get_pricing_service,
)
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


async def test_road_mode_grounds_pois_enriches_prices_and_blocks_airports(client):
    """Phase 2 end-to-end mocked check: POI grounding, strict schema, zero airports."""
    fake_bundle = DestinationPOIBundle(
        destination="Lahore, Pakistan",
        center_lat=31.5204,
        center_lon=74.3587,
        source="overpass",
        hotels=[
            DiscoveredPOI(
                name="Luxus Grand Hotel",
                category="hotel",
                subcategory="hotel",
                latitude=31.5591,
                longitude=74.3315,
                distance_to_center_km=4.9,
            ),
            DiscoveredPOI(
                name="Faletti's Hotel",
                category="hotel",
                subcategory="hotel",
                latitude=31.5588,
                longitude=74.3292,
                distance_to_center_km=5.1,
            ),
            DiscoveredPOI(
                name="Pearl Continental Lahore",
                category="hotel",
                subcategory="hotel",
                latitude=31.5521,
                longitude=74.3372,
                distance_to_center_km=4.1,
            ),
        ],
        dining=[
            DiscoveredPOI(
                name="Haveli Restaurant",
                category="dining",
                subcategory="restaurant",
                latitude=31.5882,
                longitude=74.3108,
                distance_to_center_km=8.7,
            ),
            DiscoveredPOI(
                name="Butt Karahi",
                category="dining",
                subcategory="restaurant",
                latitude=31.5640,
                longitude=74.3240,
                distance_to_center_km=5.8,
            ),
        ],
        attractions=[
            DiscoveredPOI(
                name="Shalimar Gardens",
                category="attraction",
                subcategory="park",
                latitude=31.5858,
                longitude=74.3819,
                distance_to_center_km=7.6,
            ),
            DiscoveredPOI(
                name="Badshahi Mosque",
                category="attraction",
                subcategory="historic:mosque",
                latitude=31.5881,
                longitude=74.3095,
                distance_to_center_km=8.8,
            ),
        ],
    )

    class _FakePOIDiscovery:
        async def discover_pois(self, destination: str) -> DestinationPOIBundle:
            return fake_bundle

    class _FakePricingProvider(BasePricingProvider):
        async def lookup_place_price(self, place_name, city, category, currency):
            if place_name == "Faletti's Hotel":
                return PriceLookupResult(
                    found=True,
                    estimated_price=24000.0,
                    currency=currency,
                    price_source="web_found",
                    price_note="Web snippet rate (~PKR 24000/night)",
                )
            return PriceLookupResult(
                found=False, currency=currency, price_source="ai_estimated"
            )

    llm_road_json = json.dumps(
        {
            "days": [
                {
                    "day_number": 1,
                    "title": "Road Arrival & Gardens",
                    "activities": [
                        # Deliberate airport slip to prove post-processor blocks it!
                        {
                            "time_slot": "Morning",
                            "title": "Allama Iqbal International Airport",
                            "description": "Flight arrival at airport terminal.",
                            "category": "Travel",
                            "estimated_cost": 0.0,
                        },
                        {
                            "time_slot": "Afternoon",
                            "title": "Shalimar Gardens",
                            "description": "Explore the Mughal terraced gardens.",
                            "category": "Historical",
                            "estimated_cost": 500.0,
                        },
                    ],
                },
                {
                    "day_number": 2,
                    "title": "Walled City & Return Drive",
                    "activities": [
                        {
                            "time_slot": "Morning",
                            "title": "Badshahi Mosque",
                            "description": "Tour the historic Mughal mosque.",
                            "category": "Historical",
                            "estimated_cost": 0.0,
                        }
                    ],
                },
            ],
            "transport_summary": {
                "mode": "road",
                "estimated_cost": 12000.0,
                "notes": "Round-trip fuel and M-2 Motorway tolls from Islamabad.",
                "route_tip": "Stop at Bhera service area midway on M-2.",
            },
            "hotel_options": [
                {
                    "name": "Luxus Grand Hotel",
                    "tier": "budget",
                    "estimated_price": 14000.0,
                    "price_note": "Est. per night",
                    "highlights": ["Mall Road access", "Breakfast"],
                },
                {
                    "name": "Faletti's Hotel",
                    "tier": "mid_range",
                    "estimated_price": 21000.0,
                    "price_note": "Est. per night",
                    "highlights": ["Heritage property", "Central"],
                },
                {
                    "name": "Pearl Continental Lahore",
                    "tier": "comfort",
                    "estimated_price": 35000.0,
                    "price_note": "Est. per night",
                    "highlights": ["Pool", "5-star dining"],
                },
            ],
            "dining_options": [
                {
                    "name": "Haveli Restaurant",
                    "tier": "mid_range",
                    "estimated_price": 3500.0,
                    "price_note": "Est. per person",
                    "highlights": ["Rooftop mosque view"],
                },
                {
                    "name": "Butt Karahi",
                    "tier": "budget",
                    "estimated_price": 1800.0,
                    "price_note": "Est. per person",
                    "highlights": ["Famous desi karahi"],
                },
            ],
        }
    )

    fake_http, calls = _make_fake_http([llm_road_json])
    settings = Settings(openrouter_api_key="test-key", openrouter_max_retries=0)
    road_payload = {
        "destination": "Lahore, Pakistan",
        "start_date": "2026-06-10",
        "end_date": "2026-06-11",
        "budget": 90000.0,
        "currency": "PKR",
        "interests": ["Historical", "Local Food"],
        "travel_style": "Moderate",
        "travel_mode": "road",
        "departure_city": "Islamabad",
    }

    async with fake_http:
        _override_engine(AIEngine(settings=settings, http_client=fake_http))
        app.dependency_overrides[get_poi_discovery_service] = (
            lambda: _FakePOIDiscovery()
        )
        app.dependency_overrides[get_pricing_service] = lambda: PricingService(
            _FakePricingProvider()
        )
        res = await client.post("/api/v1/itinerary/generate", json=road_payload)

    assert res.status_code == 200
    parsed = TripItineraryResponseSchema(**res.json())

    # Prompt included verified POIs & travel_mode/departure_city
    user_prompt = calls[0]["body"]["messages"][1]["content"]
    assert "<verified_real_places>" in user_prompt
    assert "Faletti's Hotel" in user_prompt
    assert "Travel mode: road" in user_prompt
    assert "Departure city: Islamabad" in user_prompt

    # Strict schema verified
    schema = calls[0]["body"]["response_format"]["json_schema"]["schema"]
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {
        "days",
        "transport_summary",
        "hotel_options",
        "dining_options",
    }

    # Zero airport activities in road mode!
    all_acts = [a for d in parsed.days for a in d.activities]
    assert all("airport" not in a.title.lower() for a in all_acts)
    assert all("flight" not in a.description.lower() for a in all_acts)
    # Overpass GPS attached directly to matched activities!
    assert all(a.verified and a.latitude is not None for a in all_acts)

    # Transport summary, hotel options & dining options enriched properly
    assert parsed.travel_mode == "road"
    assert parsed.transport_summary is not None
    assert parsed.transport_summary.mode == "road"
    assert len(parsed.hotel_options) == 3
    assert sum(1 for h in parsed.hotel_options if h.selected) == 1
    faletti = next(h for h in parsed.hotel_options if h.name == "Faletti's Hotel")
    assert faletti.selected is True
    assert faletti.verified is True
    assert faletti.latitude == 31.5588
    assert faletti.price_source == "web_found"
    assert faletti.estimated_price == 24000.0
    luxus = next(h for h in parsed.hotel_options if h.name == "Luxus Grand Hotel")
    assert luxus.price_source == "ai_estimated"
    assert len(parsed.dining_options) == 2
    assert all(d.verified for d in parsed.dining_options)
