"""Unit tests for Phase 1 schemas and Real-Data-First POI Discovery (mocked HTTP)."""

import httpx
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import (
    ItineraryResponseSchema,
    PlaceOption,
    TransportSummary,
)
from app.services.geocoding_service import GeocodingService
from app.services.poi_discovery_service import (
    MAX_ATTRACTIONS,
    MAX_DINING,
    MAX_HOTELS,
    POIDiscoveryService,
    build_overpass_query,
)

pytestmark = pytest.mark.anyio

BASE_TRIP = {
    "destination": "Lahore, Pakistan",
    "start_date": "2026-06-10",
    "end_date": "2026-06-12",
    "budget": 500.0,
    "currency": "USD",
    "interests": ["Historical", "Local Food"],
    "travel_style": "Moderate",
}


# --- Phase 1 Request & Response Schema Backward Compatibility --------------


def test_trip_request_travel_mode_and_departure_city():
    # Backward-compatible defaults when omitted
    default_req = TripRequestSchema(**BASE_TRIP)
    assert default_req.travel_mode == "air"
    assert default_req.departure_city is None

    # All 5 supported modes accepted and departure_city sanitized
    for mode in ("air", "road", "train", "bus", "bike"):
        req = TripRequestSchema(
            **BASE_TRIP,
            travel_mode=mode,
            departure_city="  Islamabad\x00  ",
        )
        assert req.travel_mode == mode
        assert req.departure_city == "Islamabad"

    # Blank/control-only departure_city normalizes to None
    blank_dep = TripRequestSchema(**BASE_TRIP, departure_city="  \n\t ")
    assert blank_dep.departure_city is None

    # Invalid travel_mode rejected
    with pytest.raises(ValidationError):
        TripRequestSchema(**BASE_TRIP, travel_mode="spaceship")

    # Departure city > 80 chars rejected
    with pytest.raises(ValidationError):
        TripRequestSchema(**BASE_TRIP, departure_city="A" * 81)


def test_itinerary_response_schema_backward_compatible_with_comparisons():
    minimal = ItineraryResponseSchema(
        trip_id="itinerary_phase1",
        destination="Lahore, Pakistan",
        duration_days=1,
        total_estimated_cost=40.0,
        currency="USD",
        days=[],
    )
    assert minimal.travel_mode == "air"
    assert minimal.transport_summary is None
    assert minimal.hotel_options == []
    assert minimal.dining_options == []

    enriched = ItineraryResponseSchema(
        trip_id="itinerary_phase1b",
        destination="Lahore, Pakistan",
        duration_days=2,
        total_estimated_cost=180.0,
        currency="USD",
        days=[],
        travel_mode="road",
        transport_summary=TransportSummary(
            mode="road",
            estimated_cost=35.0,
            price_source="ai_estimated",
            notes="M-2 Motorway fuel + tolls.",
            route_tip="Stop at Bhera service area.",
        ),
        hotel_options=[
            PlaceOption(
                option_id="hotel_01",
                name="Pearl Continental Lahore",
                tier="comfort",
                estimated_price=110.0,
                total_estimated_cost=220.0,
                price_source="ai_estimated",
                price_note="Est. per night",
                latitude=31.5521,
                longitude=74.3372,
                verified=True,
                distance_to_center_km=2.4,
                highlights=["Pool", "Central Mall Road"],
                selected=True,
            )
        ],
        dining_options=[
            PlaceOption(
                option_id="dining_01",
                name="Haveli Restaurant",
                tier="mid_range",
                estimated_price=18.0,
                total_estimated_cost=18.0,
                price_source="web_found",
                price_note="Avg meal per person",
                latitude=31.5882,
                longitude=74.3108,
                verified=True,
                distance_to_center_km=4.1,
                highlights=["Badshahi Mosque rooftop view"],
            )
        ],
    )
    assert enriched.transport_summary is not None
    assert enriched.transport_summary.mode == "road"
    assert enriched.hotel_options[0].selected is True
    assert enriched.dining_options[0].price_source == "web_found"


# --- Overpass Query, Parsing, Deduplication & Capping ----------------------


def _nominatim_lahore_response() -> httpx.Response:
    return httpx.Response(
        200,
        json=[
            {
                "lat": "31.5204",
                "lon": "74.3587",
                "display_name": "Lahore, Punjab, Pakistan",
                "boundingbox": ["31.35", "31.65", "74.15", "74.50"],
            }
        ],
    )


def test_build_overpass_query_contains_required_tag_filters():
    ql = build_overpass_query((31.35, 74.15, 31.65, 74.5))
    assert "hotel|guest_house|hostel|resort|motel" in ql
    assert "restaurant|cafe|fast_food" in ql
    assert "attraction|museum|viewpoint|park|gallery" in ql
    assert 'nwr["historic"]["name"]' in ql
    assert "out center tags;" in ql


async def test_overpass_parsing_deduplication_and_caps():
    overpass_calls = 0

    elements: list[dict] = [
        # Valid node hotel + duplicate case/whitespace way hotel (farther)
        {
            "type": "node",
            "lat": 31.525,
            "lon": 74.360,
            "tags": {"name": "Pearl Continental", "tourism": "hotel", "stars": "5"},
        },
        {
            "type": "way",
            "center": {"lat": 31.590, "lon": 74.410},
            "tags": {"name": "  pearl   continental ", "tourism": "hotel"},
        },
        # Invalid entries that must be skipped safely
        {"type": "node", "lat": 31.52, "lon": 74.36, "tags": {"tourism": "hotel"}},
        {
            "type": "node",
            "lat": 999.0,
            "lon": 74.36,
            "tags": {"name": "Bad Lat Hotel", "tourism": "hotel"},
        },
        {
            "type": "node",
            "lat": 31.52,
            "lon": 74.36,
            "tags": {"name": "Random Shop", "shop": "bakery"},
        },
    ]
    # Add 16 distinct hotels -> should cap at MAX_HOTELS (12)
    for i in range(1, 17):
        elements.append(
            {
                "type": "node",
                "lat": 31.52 + i * 0.002,
                "lon": 74.36,
                "tags": {
                    "name": f"Hotel Oasis {i}",
                    "tourism": "guest_house" if i % 2 == 0 else "resort",
                },
            }
        )
    # Add 20 distinct restaurants -> should cap at MAX_DINING (15)
    for i in range(1, 21):
        elements.append(
            {
                "type": "way",
                "center": {"lat": 31.52 + i * 0.001, "lon": 74.355},
                "tags": {
                    "name": f"Lahori Kitchen {i}",
                    "amenity": "cafe" if i % 3 == 0 else "restaurant",
                    "cuisine": "pakistani",
                },
            }
        )
    # Add 22 distinct attractions (including historic=*) -> cap at MAX_ATTRACTIONS (18)
    for i in range(1, 23):
        tags = (
            {"name": f"Historic Gate {i}", "historic": "monument"}
            if i % 2 == 0
            else {"name": f"City Museum {i}", "tourism": "museum"}
        )
        elements.append(
            {
                "type": "node",
                "lat": 31.52 + i * 0.0015,
                "lon": 74.35,
                "tags": tags,
            }
        )

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal overpass_calls
        url = str(request.url)
        if "nominatim" in url:
            return _nominatim_lahore_response()
        if "overpass" in url:
            overpass_calls += 1
            return httpx.Response(200, json={"elements": elements})
        return httpx.Response(404)

    settings = Settings(nominatim_min_interval_seconds=0.0, poi_cache_ttl_seconds=86400)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        geocoder = GeocodingService(settings=settings, http_client=http)
        service = POIDiscoveryService(
            settings=settings, geocoding_service=geocoder, http_client=http
        )
        bundle = await service.discover_pois("Lahore, Pakistan")
        # Second call with different casing/spacing must hit 24h cache!
        cached_bundle = await service.discover_pois("  lahore,   pakistan ")

    assert bundle.source == "overpass"
    assert len(bundle.hotels) == MAX_HOTELS
    assert len(bundle.dining) == MAX_DINING
    assert len(bundle.attractions) == MAX_ATTRACTIONS
    # Closer "Pearl Continental" kept and deduplicated
    pc_matches = [h for h in bundle.hotels if h.name.lower() == "pearl continental"]
    assert len(pc_matches) == 1
    assert pc_matches[0].latitude == 31.525
    # Verify sorted by distance_to_center_km ascending
    dists = [h.distance_to_center_km for h in bundle.hotels]
    assert dists == sorted(dists)
    # Verify cache hit prevented any extra Overpass HTTP call
    assert overpass_calls == 1
    assert cached_bundle == bundle


async def test_overpass_timeout_triggers_nominatim_category_fallback():
    nominatim_queries: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "overpass" in url:
            raise httpx.ReadTimeout("Overpass timed out")
        q = request.url.params.get("q", "").lower()
        nominatim_queries.append(q)
        if q == "lahore, pakistan":
            return _nominatim_lahore_response()
        if q.startswith("hotel in"):
            return httpx.Response(
                200,
                json=[
                    {
                        "name": "Nishat Hotel",
                        "type": "hotel",
                        "lat": "31.5112",
                        "lon": "74.3490",
                        "display_name": "Nishat Hotel, Gulberg, Lahore",
                    }
                ],
            )
        if q.startswith("restaurant in"):
            return httpx.Response(
                200,
                json=[
                    {
                        "name": "Butt Karahi",
                        "type": "restaurant",
                        "lat": "31.5640",
                        "lon": "74.3240",
                        "display_name": "Butt Karahi, Lakshmi Chowk, Lahore",
                    }
                ],
            )
        if q.startswith("tourist attraction in"):
            return httpx.Response(
                200,
                json=[
                    {
                        "name": "Badshahi Mosque",
                        "type": "attraction",
                        "lat": "31.5881",
                        "lon": "74.3095",
                        "display_name": "Badshahi Mosque, Lahore",
                    }
                ],
            )
        return httpx.Response(200, json=[])

    settings = Settings(nominatim_min_interval_seconds=0.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        geocoder = GeocodingService(settings=settings, http_client=http)
        service = POIDiscoveryService(
            settings=settings, geocoding_service=geocoder, http_client=http
        )
        bundle = await service.discover_pois("Lahore, Pakistan")

    assert bundle.source == "nominatim"
    assert [h.name for h in bundle.hotels] == ["Nishat Hotel"]
    assert [d.name for d in bundle.dining] == ["Butt Karahi"]
    assert [a.name for a in bundle.attractions] == ["Badshahi Mosque"]
    assert all(p.source == "nominatim" for p in bundle.hotels + bundle.dining)
    assert any(q.startswith("hotel in") for q in nominatim_queries)
    assert any(q.startswith("restaurant in") for q in nominatim_queries)
    assert any(q.startswith("tourist attraction in") for q in nominatim_queries)


async def test_sparse_overpass_merges_with_nominatim_as_hybrid():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "overpass" in url:
            # Only 1 hotel and 0 dining/attractions -> triggers hybrid fallback
            return httpx.Response(
                200,
                json={
                    "elements": [
                        {
                            "type": "node",
                            "lat": 31.525,
                            "lon": 74.360,
                            "tags": {"name": "Luxus Grand Hotel", "tourism": "hotel"},
                        }
                    ]
                },
            )
        q = request.url.params.get("q", "").lower()
        if q == "lahore, pakistan":
            return _nominatim_lahore_response()
        if q.startswith("hotel in"):
            return httpx.Response(
                200,
                json=[
                    {
                        "name": "Luxus Grand Hotel",
                        "lat": "31.525",
                        "lon": "74.360",
                        "display_name": "Luxus Grand Hotel, Lahore",
                    },
                    {
                        "name": "Faletti's Hotel",
                        "lat": "31.559",
                        "lon": "74.329",
                        "display_name": "Faletti's Hotel, Lahore",
                    },
                ],
            )
        return httpx.Response(200, json=[])

    settings = Settings(nominatim_min_interval_seconds=0.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        geocoder = GeocodingService(settings=settings, http_client=http)
        service = POIDiscoveryService(
            settings=settings, geocoding_service=geocoder, http_client=http
        )
        bundle = await service.discover_pois("Lahore, Pakistan")

    assert bundle.source == "hybrid"
    assert len(bundle.hotels) == 2
    by_name = {h.name: h for h in bundle.hotels}
    # Duplicate hotel prefers Overpass over Nominatim
    assert by_name["Luxus Grand Hotel"].source == "overpass"
    assert by_name["Faletti's Hotel"].source == "nominatim"


async def test_unresolvable_destination_returns_empty_bundle():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[])

    settings = Settings(nominatim_min_interval_seconds=0.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        geocoder = GeocodingService(settings=settings, http_client=http)
        service = POIDiscoveryService(
            settings=settings, geocoding_service=geocoder, http_client=http
        )
        bundle = await service.discover_pois("Nowhereville Unknown 999")

    assert bundle.source == "empty"
    assert bundle.hotels == []
    assert bundle.dining == []
    assert bundle.attractions == []
