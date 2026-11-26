"""Tests for the health endpoint and core Pydantic schemas (M1)."""

from datetime import datetime

import pytest
from pydantic import ValidationError

from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import TripItineraryResponseSchema

pytestmark = pytest.mark.anyio

VALID_TRIP = {
    "destination": "Hunza Valley, Pakistan",
    "start_date": "2026-06-10",
    "end_date": "2026-06-14",
    "budget": 500.0,
    "currency": "USD",
    "interests": ["Nature", "Photography", "Local Food", "Hiking"],
    "travel_style": "Moderate",
}

PRD_SAMPLE_RESPONSE = {
    "trip_id": "itinerary_9f8a2b1c",
    "destination": "Hunza Valley, Pakistan",
    "duration_days": 5,
    "total_estimated_cost": 420.0,
    "currency": "USD",
    "days": [
        {
            "day_number": 1,
            "title": "Arrival & Karimabad Exploration",
            "activities": [
                {
                    "activity_id": "act_01",
                    "time_slot": "Morning",
                    "title": "Visit Baltit Fort",
                    "description": "Explore the 700-year-old historic fort.",
                    "category": "Historical",
                    "estimated_cost": 15.0,
                    "latitude": 36.3256,
                    "longitude": 74.6678,
                    "verified": True,
                }
            ],
        }
    ],
}


# --- Health endpoint -------------------------------------------------------


async def test_health_check_returns_200(client):
    response = await client.get("/api/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["environment"] == "development"
    # Timestamp must be a valid timezone-aware ISO-8601 datetime.
    assert datetime.fromisoformat(body["timestamp"]).tzinfo is not None


async def test_unknown_route_returns_404(client):
    response = await client.get("/api/v1/does-not-exist")
    assert response.status_code == 404


async def test_openapi_docs_available(client):
    assert (await client.get("/docs")).status_code == 200
    assert (await client.get("/redoc")).status_code == 200
    spec_res = await client.get("/openapi.json")
    assert spec_res.status_code == 200
    spec = spec_res.json()
    assert spec["info"]["version"] == "1.0.0"
    assert set(spec["paths"].keys()) >= {
        "/api/v1/health",
        "/api/v1/itinerary/generate",
        "/api/v1/itinerary/regenerate-slot",
        "/api/v1/weather",
    }
    tag_names = {tag["name"] for tag in spec.get("tags", [])}
    assert {"Health", "Itinerary", "Weather"} <= tag_names


# --- Request schema --------------------------------------------------------


def test_trip_request_accepts_prd_example():
    trip = TripRequestSchema(**VALID_TRIP)
    assert trip.duration_days == 5  # matches PRD sample response
    assert trip.currency == "USD"


def test_trip_request_normalises_currency_case():
    trip = TripRequestSchema(**{**VALID_TRIP, "currency": "pkr"})
    assert trip.currency == "PKR"


@pytest.mark.parametrize(
    "override",
    [
        {"end_date": "2026-06-09"},  # end before start
        {"budget": 0},
        {"budget": -10},
        {"currency": "US"},
        {"currency": "US1"},
        {"interests": []},
        {"interests": ["  "]},
        {"destination": ""},
        {"start_date": "not-a-date"},
    ],
)
def test_trip_request_rejects_invalid_input(override):
    with pytest.raises(ValidationError):
        TripRequestSchema(**{**VALID_TRIP, **override})


def test_trip_request_defaults_currency_to_pkr():
    payload = {k: v for k, v in VALID_TRIP.items() if k != "currency"}
    trip = TripRequestSchema(**payload)
    assert trip.currency == "PKR"


def test_trip_request_requires_all_fields():
    required_fields = [f for f in VALID_TRIP if f != "currency"]
    for field in required_fields:
        payload = {k: v for k, v in VALID_TRIP.items() if k != field}
        with pytest.raises(ValidationError):
            TripRequestSchema(**payload)


# --- Response schema -------------------------------------------------------


def test_response_schema_accepts_prd_sample():
    itinerary = TripItineraryResponseSchema(**PRD_SAMPLE_RESPONSE)
    activity = itinerary.days[0].activities[0]
    assert activity.verified is True
    assert activity.latitude == 36.3256


def test_activity_defaults_to_unverified_without_coordinates():
    sample = PRD_SAMPLE_RESPONSE["days"][0]["activities"][0]
    raw = {
        k: v
        for k, v in sample.items()
        if k not in ("latitude", "longitude", "verified")
    }
    payload = {
        **PRD_SAMPLE_RESPONSE,
        "days": [{**PRD_SAMPLE_RESPONSE["days"][0], "activities": [raw]}],
    }
    activity = TripItineraryResponseSchema(**payload).days[0].activities[0]
    assert activity.latitude is None
    assert activity.longitude is None
    assert activity.verified is False


def test_response_schema_rejects_out_of_range_latitude():
    activity = {**PRD_SAMPLE_RESPONSE["days"][0]["activities"][0], "latitude": 120}
    payload = {
        **PRD_SAMPLE_RESPONSE,
        "days": [{**PRD_SAMPLE_RESPONSE["days"][0], "activities": [activity]}],
    }
    with pytest.raises(ValidationError):
        TripItineraryResponseSchema(**payload)
