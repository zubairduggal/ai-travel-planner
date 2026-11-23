"""Unit & integration tests for geocoding, Haversine feasibility, and weather (M3)."""

import json
import os
import time
from types import SimpleNamespace

import httpx
import pytest

from app.api.v1.endpoints.weather import (
    describe_weather_code,
    get_weather_http_client,
)
from app.core.config import Settings
from app.main import app
from app.models.response_schemas import (
    ActivitySchema,
    DayPlanSchema,
    TripItineraryResponseSchema,
)
from app.services.ai_engine import AIEngine, get_ai_engine
from app.services.geocoding_service import (
    GeocodingService,
    extract_place_name,
    get_geocoding_service,
)
from app.utils.distance_calculator import (
    estimate_travel_minutes,
    evaluate_day_feasibility,
    haversine_km,
)

pytestmark = pytest.mark.anyio


# --- Haversine & distance feasibility --------------------------------------


def test_haversine_known_distances():
    assert haversine_km(36.3256, 74.6678, 36.3256, 74.6678) == 0.0

    # Baltit Fort -> Attabad Lake (~15.8 km straight line)
    hunza_leg = haversine_km(36.3256, 74.6678, 36.3274, 74.8439)
    assert 14.0 <= hunza_leg <= 17.5

    # Islamabad -> Lahore (~269 km straight line)
    isb_lhr = haversine_km(33.6844, 73.0479, 31.5204, 74.3587)
    assert 260.0 <= isb_lhr <= 280.0


def test_estimate_travel_minutes():
    assert estimate_travel_minutes(0.0) == 0
    assert estimate_travel_minutes(20.0, avg_speed_kmh=40.0) == 30
    with pytest.raises(ValueError):
        estimate_travel_minutes(10.0, avg_speed_kmh=0)


def test_evaluate_day_feasibility_within_threshold():
    activities = [
        ActivitySchema(
            activity_id="act_01",
            time_slot="Morning",
            title="Visit Baltit Fort",
            description="Historic fort.",
            category="Historical",
            estimated_cost=15.0,
            latitude=36.3256,
            longitude=74.6678,
            verified=True,
        ),
        ActivitySchema(
            activity_id="act_02",
            time_slot="Afternoon",
            title="Visit Altit Fort",
            description="Ancient fort nearby.",
            category="Historical",
            estimated_cost=10.0,
            latitude=36.3144,
            longitude=74.6819,
            verified=True,
        ),
    ]
    result = evaluate_day_feasibility(activities, max_leg_km=50.0)

    assert result.feasible is True
    assert result.warnings == []
    assert result.total_distance_km is not None
    assert 1.0 <= result.total_distance_km <= 3.0
    assert len(result.legs) == 1


def test_evaluate_day_feasibility_flags_excessive_distance():
    activities = [
        ActivitySchema(
            activity_id="act_01",
            time_slot="Morning",
            title="Visit Baltit Fort",
            description="In Hunza.",
            category="Historical",
            estimated_cost=15.0,
            latitude=36.3256,
            longitude=74.6678,
            verified=True,
        ),
        ActivitySchema(
            activity_id="act_02",
            time_slot="Afternoon",
            title="Visit Badshahi Mosque",
            description="In Lahore (far away!).",
            category="Historical",
            estimated_cost=0.0,
            latitude=31.5881,
            longitude=74.3095,
            verified=True,
        ),
    ]
    result = evaluate_day_feasibility(activities, max_leg_km=50.0)

    assert result.feasible is False
    assert len(result.warnings) == 1
    assert "Baltit Fort" in result.warnings[0]
    assert "Badshahi Mosque" in result.warnings[0]


def test_evaluate_day_feasibility_handles_few_verified_points():
    unverified = [
        ActivitySchema(
            activity_id="act_01",
            time_slot="Morning",
            title="Mystery Place",
            description="No GPS.",
            category="Culture",
            estimated_cost=5.0,
        )
    ]
    res_none = evaluate_day_feasibility(unverified)
    assert res_none.total_distance_km is None
    assert res_none.feasible is True

    one_verified = [
        unverified[0].model_copy(
            update={"latitude": 36.3256, "longitude": 74.6678, "verified": True}
        )
    ]
    res_one = evaluate_day_feasibility(one_verified)
    assert res_one.total_distance_km == 0.0
    assert res_one.feasible is True


# --- Place name cleaning ---------------------------------------------------


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        ("Visit Baltit Fort", "Baltit Fort"),
        ("Boat ride at Attabad Lake", "Attabad Lake"),
        ("Sunset at Eagle's Nest Viewpoint", "Eagle's Nest Viewpoint"),
        ("Walk across Hussaini Suspension Bridge", "Hussaini Suspension Bridge"),
        ("Baltit Fort", "Baltit Fort"),
    ],
)
def test_extract_place_name(title, expected):
    assert extract_place_name(title) == expected


# --- Geocoding service (Nominatim + cache + throttle + Google fallback) ----


async def test_nominatim_search_headers_params_and_caching():
    seen_requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen_requests.append(request)
        return httpx.Response(
            200,
            json=[
                {
                    "lat": "36.325600",
                    "lon": "74.667800",
                    "display_name": "Baltit Fort, Karimabad, Hunza, Pakistan",
                    "boundingbox": ["36.32", "36.33", "74.66", "74.67"],
                }
            ],
        )

    settings = Settings(
        nominatim_user_agent="TestTravelApp/1.0 (qa@example.com)",
        nominatim_min_interval_seconds=0.0,
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = GeocodingService(settings=settings, http_client=http)
        first = await service.geocode_place("Baltit Fort, Hunza")
        second = await service.geocode_place("  baltit fort, hunza  ")

    assert first is not None
    assert first == second
    assert first.latitude == 36.3256
    assert first.longitude == 74.6678
    assert first.boundingbox == (36.32, 36.33, 74.66, 74.67)
    assert first.provider == "nominatim"
    # Second call must hit cache (only 1 HTTP request total).
    assert len(seen_requests) == 1
    assert (
        seen_requests[0].headers["User-Agent"] == "TestTravelApp/1.0 (qa@example.com)"
    )
    assert seen_requests[0].url.params["format"] == "jsonv2"
    assert seen_requests[0].url.params["limit"] == "1"


async def test_nominatim_throttle_enforces_min_interval():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    settings = Settings(nominatim_min_interval_seconds=0.06)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = GeocodingService(settings=settings, http_client=http)
        start = time.monotonic()
        await service.geocode_place("Place A")
        await service.geocode_place("Place B")
        elapsed = time.monotonic() - start

    assert elapsed >= 0.05


async def test_nominatim_gracefully_handles_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="Service Unavailable")

    settings = Settings(nominatim_min_interval_seconds=0.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = GeocodingService(settings=settings, http_client=http)
        result = await service.geocode_place("Baltit Fort")

    assert result is None


async def test_google_places_fallback_when_nominatim_misses():
    seen_requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen_requests.append(request)
        if "nominatim" in str(request.url):
            return httpx.Response(200, json=[])
        return httpx.Response(
            200,
            json={
                "places": [
                    {
                        "displayName": {"text": "Eagle's Nest Hotel"},
                        "location": {"latitude": 36.3202, "longitude": 74.6897},
                    }
                ]
            },
        )

    settings = Settings(
        nominatim_min_interval_seconds=0.0,
        google_places_api_key="fake-places-key",
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = GeocodingService(settings=settings, http_client=http)
        match = await service.geocode_place("Eagle's Nest Viewpoint, Hunza")

    assert match is not None
    assert match.provider == "google_places"
    assert match.latitude == 36.3202
    assert match.longitude == 74.6897
    assert len(seen_requests) == 2
    places_req = seen_requests[1]
    assert places_req.headers["X-Goog-Api-Key"] == "fake-places-key"
    assert (
        places_req.headers["X-Goog-FieldMask"] == "places.displayName,places.location"
    )


async def test_verify_itinerary_populates_coordinates_viewbox_and_feasibility():
    seen_params: list[dict[str, str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        q = request.url.params.get("q", "").lower()
        seen_params.append(dict(request.url.params))
        if q == "hunza valley, pakistan":
            return httpx.Response(
                200,
                json=[
                    {
                        "lat": "36.3167",
                        "lon": "74.6500",
                        "display_name": "Hunza Valley, Pakistan",
                        "boundingbox": ["36.20", "36.50", "74.50", "74.90"],
                    }
                ],
            )
        if "baltit fort" in q:
            return httpx.Response(
                200,
                json=[
                    {"lat": "36.3256", "lon": "74.6678", "display_name": "Baltit Fort"}
                ],
            )
        if "attabad lake" in q:
            return httpx.Response(
                200,
                json=[
                    {"lat": "36.3274", "lon": "74.8439", "display_name": "Attabad Lake"}
                ],
            )
        return httpx.Response(200, json=[])

    itinerary = TripItineraryResponseSchema(
        trip_id="itinerary_test0001",
        destination="Hunza Valley, Pakistan",
        duration_days=1,
        total_estimated_cost=50.0,
        currency="USD",
        days=[
            DayPlanSchema(
                day_number=1,
                title="Karimabad & Attabad",
                activities=[
                    ActivitySchema(
                        activity_id="act_01",
                        time_slot="Morning",
                        title="Visit Baltit Fort",
                        description="Historic fort.",
                        category="Historical",
                        estimated_cost=15.0,
                    ),
                    ActivitySchema(
                        activity_id="act_02",
                        time_slot="Afternoon",
                        title="Boat ride at Attabad Lake",
                        description="Turquoise lake.",
                        category="Nature",
                        estimated_cost=35.0,
                    ),
                    ActivitySchema(
                        activity_id="act_03",
                        time_slot="Evening",
                        title="Nonexistent Secret Cafe",
                        description="Not in OSM.",
                        category="Food",
                        estimated_cost=0.0,
                    ),
                ],
            )
        ],
    )

    settings = Settings(
        nominatim_min_interval_seconds=0.0, max_same_day_distance_km=50.0
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = GeocodingService(settings=settings, http_client=http)
        verified = await service.verify_itinerary(itinerary)

    day1 = verified.days[0]
    assert day1.activities[0].verified is True
    assert day1.activities[0].latitude == 36.3256
    assert day1.activities[0].longitude == 74.6678

    assert day1.activities[1].verified is True
    assert day1.activities[1].latitude == 36.3274

    assert day1.activities[2].verified is False
    assert day1.activities[2].latitude is None
    assert day1.activities[2].longitude is None

    assert day1.feasible is True
    assert day1.total_distance_km is not None
    assert 14.0 <= day1.total_distance_km <= 17.5

    # Activity lookup must include destination viewbox (min_lon,min_lat,max_lon,max_lat)
    assert seen_params[1]["viewbox"] == "74.5,36.2,74.9,36.5"
    assert seen_params[1]["bounded"] == "0"


async def test_itinerary_endpoint_integrates_geocoding(client):
    llm_json = json.dumps(
        {
            "days": [
                {
                    "day_number": 1,
                    "title": "Karimabad Highlights",
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

    class _Models:
        async def generate_content(self, **kwargs):
            return SimpleNamespace(text=llm_json)

    fake_ai = AIEngine(
        settings=Settings(gemini_api_key="test"),
        client=SimpleNamespace(aio=SimpleNamespace(models=_Models())),
    )

    def geo_handler(request: httpx.Request) -> httpx.Response:
        q = request.url.params.get("q", "").lower()
        if "baltit" in q:
            return httpx.Response(
                200,
                json=[
                    {"lat": "36.3256", "lon": "74.6678", "display_name": "Baltit Fort"}
                ],
            )
        return httpx.Response(200, json=[])

    async with httpx.AsyncClient(transport=httpx.MockTransport(geo_handler)) as http:
        geocoder = GeocodingService(
            settings=Settings(nominatim_min_interval_seconds=0.0),
            http_client=http,
        )
        app.dependency_overrides[get_ai_engine] = lambda: fake_ai
        app.dependency_overrides[get_geocoding_service] = lambda: geocoder

        response = await client.post(
            "/api/v1/itinerary/generate",
            json={
                "destination": "Hunza Valley, Pakistan",
                "start_date": "2026-06-10",
                "end_date": "2026-06-10",
                "budget": 100.0,
                "currency": "USD",
                "interests": ["History"],
                "travel_style": "Moderate",
            },
        )

    assert response.status_code == 200
    act = response.json()["days"][0]["activities"][0]
    assert act["verified"] is True
    assert act["latitude"] == 36.3256
    assert act["longitude"] == 74.6678


# --- Weather endpoint (Open-Meteo proxy) -----------------------------------


def test_describe_weather_code():
    assert describe_weather_code(0) == "Clear sky"
    assert describe_weather_code(None) == "Unknown"
    assert describe_weather_code(999) == "Weather code 999"


async def test_weather_endpoint_success(client):
    sample = {
        "latitude": 36.32,
        "longitude": 74.67,
        "timezone": "Asia/Karachi",
        "daily": {
            "time": ["2026-06-10", "2026-06-11"],
            "temperature_2m_max": [24.5, 22.1],
            "temperature_2m_min": [11.0, 10.2],
            "precipitation_probability_max": [10, 45],
            "weather_code": [0, 61],
        },
    }

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(200, json=sample))
    ) as http:
        app.dependency_overrides[get_weather_http_client] = lambda: http
        response = await client.get(
            "/api/v1/weather", params={"lat": 36.32, "lon": 74.67, "days": 2}
        )

    assert response.status_code == 200
    body = response.json()
    assert body["timezone"] == "Asia/Karachi"
    assert len(body["daily"]) == 2
    assert body["daily"][0]["condition"] == "Clear sky"
    assert body["daily"][1]["condition"] == "Slight rain"


async def test_weather_endpoint_handles_timeout_and_upstream_error(client):
    def raise_timeout(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow")

    async with httpx.AsyncClient(transport=httpx.MockTransport(raise_timeout)) as http:
        app.dependency_overrides[get_weather_http_client] = lambda: http
        res_timeout = await client.get(
            "/api/v1/weather", params={"lat": 36.32, "lon": 74.67}
        )
    assert res_timeout.status_code == 504
    assert res_timeout.json()["error"]["code"] == "EXTERNAL_SERVICE_TIMEOUT"

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(500))
    ) as http:
        app.dependency_overrides[get_weather_http_client] = lambda: http
        res_err = await client.get(
            "/api/v1/weather", params={"lat": 36.32, "lon": 74.67}
        )
    assert res_err.status_code == 502
    assert res_err.json()["error"]["code"] == "EXTERNAL_SERVICE_ERROR"


async def test_weather_endpoint_validates_coordinates(client):
    response = await client.get("/api/v1/weather", params={"lat": 95.0, "lon": 74.67})
    assert response.status_code == 422


# --- Optional live Nominatim GPS precision test ----------------------------


@pytest.mark.live
@pytest.mark.skipif(
    os.getenv("RUN_LIVE_TESTS") != "1",
    reason="Set RUN_LIVE_TESTS=1 to run live Nominatim precision tests.",
)
async def test_live_nominatim_precision_baltit_fort():
    service = GeocodingService(settings=Settings())
    match = await service.geocode_place("Baltit Fort, Hunza, Pakistan")

    assert match is not None
    # Confirm GPS coordinate is within 5 km of real Baltit Fort (36.3256, 74.6678).
    error_km = haversine_km(match.latitude, match.longitude, 36.3256, 74.6678)
    assert error_km <= 5.0
