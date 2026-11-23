"""Geocoding & location verification service (M3).

Primary provider: OpenStreetMap Nominatim (`/search?format=jsonv2&limit=1`).
Policy compliance built in:
- Custom `User-Agent` header (`settings.nominatim_user_agent`).
- Global async rate limit (`<= 1 req/sec` via `nominatim_min_interval_seconds`).
- Local query cache to avoid duplicate lookups for the same place.
- Destination `viewbox` biasing so common landmark names resolve in the right region.

Optional fallback: Google Places API (New) Text Search when
`GOOGLE_PLACES_API_KEY` is configured (strictly using `X-Goog-FieldMask`
for Pro SKU fields only: `places.displayName,places.location`).
"""

import asyncio
import logging
import re
import time
from dataclasses import dataclass
from functools import lru_cache

import httpx

from app.core.config import Settings, get_settings
from app.models.response_schemas import (
    ActivitySchema,
    DayPlanSchema,
    TripItineraryResponseSchema,
)
from app.utils.distance_calculator import evaluate_day_feasibility

logger = logging.getLogger(__name__)

# Leading action verbs commonly produced by LLMs in activity titles.
_ACTION_PREFIX_RE = re.compile(
    r"^(?:"
    r"visit|explore|walk(?:\s+across|\s+around|\s+along)?|tour|"
    r"hike(?:\s+to|\s+at)?|trek(?:\s+to)?|boat\s+ride\s+(?:at|on)|"
    r"sunset\s+(?:at|from)|sunrise\s+(?:at|from)|"
    r"(?:breakfast|lunch|dinner|coffee|tea|brunch)\s+at|"
    r"shopping\s+at|relax\s+at|stroll\s+(?:through|along|at)|"
    r"discover|experience|admire|photograph"
    r")\s+(?:the\s+)?",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class GeoLocation:
    """Verified coordinate match returned by a geocoding provider."""

    latitude: float
    longitude: float
    display_name: str
    boundingbox: tuple[float, float, float, float] | None = None
    provider: str = "nominatim"


def extract_place_name(activity_title: str) -> str:
    """Strip common verb prefixes like 'Visit Baltit Fort' -> 'Baltit Fort'."""
    cleaned = activity_title.strip()
    stripped = _ACTION_PREFIX_RE.sub("", cleaned).strip(" -:,.")
    return stripped or cleaned


def _format_viewbox(bbox: tuple[float, float, float, float]) -> str:
    """Convert Nominatim boundingbox (min_lat, max_lat, min_lon, max_lon) to viewbox.

    Nominatim's `viewbox` expects `xmin,ymin,xmax,ymax` -> `min_lon,min_lat,max_lon,max_lat`.
    """
    min_lat, max_lat, min_lon, max_lon = bbox
    return f"{min_lon},{min_lat},{max_lon},{max_lat}"


class GeocodingService:
    """Verifies place names against Nominatim (and optional Google Places)."""

    def __init__(
        self,
        settings: Settings,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._settings = settings
        self._http_client = http_client
        self._cache: dict[str, GeoLocation | None] = {}
        self._throttle_lock = asyncio.Lock()
        self._last_nominatim_call: float | None = None

    async def _throttle_nominatim(self) -> None:
        """Enforce Nominatim's 1 request/second global rate limit."""
        min_interval = self._settings.nominatim_min_interval_seconds
        if min_interval <= 0:
            return
        async with self._throttle_lock:
            now = time.monotonic()
            if self._last_nominatim_call is not None:
                elapsed = now - self._last_nominatim_call
                if elapsed < min_interval:
                    await asyncio.sleep(min_interval - elapsed)
            self._last_nominatim_call = time.monotonic()

    async def _request(
        self,
        method: str,
        url: str,
        *,
        params: dict[str, str | int] | None = None,
        headers: dict[str, str] | None = None,
        json_body: dict[str, object] | None = None,
    ) -> httpx.Response:
        if self._http_client is not None:
            return await self._http_client.request(
                method,
                url,
                params=params,
                headers=headers,
                json=json_body,
                timeout=self._settings.geocoding_timeout_seconds,
            )
        async with httpx.AsyncClient(
            timeout=self._settings.geocoding_timeout_seconds
        ) as client:
            return await client.request(
                method, url, params=params, headers=headers, json=json_body
            )

    async def _search_nominatim(
        self,
        query: str,
        *,
        viewbox: tuple[float, float, float, float] | None = None,
    ) -> GeoLocation | None:
        """Query OpenStreetMap Nominatim `/search?format=jsonv2&limit=1`."""
        await self._throttle_nominatim()

        params: dict[str, str | int] = {
            "q": query,
            "format": "jsonv2",
            "limit": 1,
        }
        if viewbox is not None:
            params["viewbox"] = _format_viewbox(viewbox)
            params["bounded"] = 0

        headers = {
            "User-Agent": self._settings.nominatim_user_agent,
            "Accept": "application/json",
        }
        url = f"{self._settings.nominatim_base_url.rstrip('/')}/search"

        try:
            response = await self._request("GET", url, params=params, headers=headers)
            response.raise_for_status()
            results = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Nominatim lookup failed for '%s': %s", query, exc)
            return None

        if not isinstance(results, list) or not results:
            return None

        top = results[0]
        try:
            lat = round(float(top["lat"]), 6)
            lon = round(float(top["lon"]), 6)
        except (KeyError, TypeError, ValueError):
            return None

        bbox: tuple[float, float, float, float] | None = None
        raw_bbox = top.get("boundingbox")
        if isinstance(raw_bbox, list) and len(raw_bbox) == 4:
            try:
                bbox = (
                    float(raw_bbox[0]),
                    float(raw_bbox[1]),
                    float(raw_bbox[2]),
                    float(raw_bbox[3]),
                )
            except (TypeError, ValueError):
                bbox = None

        return GeoLocation(
            latitude=lat,
            longitude=lon,
            display_name=str(top.get("display_name", query)),
            boundingbox=bbox,
            provider="nominatim",
        )

    async def _search_google_places(self, query: str) -> GeoLocation | None:
        """Optional fallback using Google Places API (New) Text Search."""
        api_key = self._settings.google_places_api_key
        if not api_key:
            return None

        url = "https://places.googleapis.com/v1/places:searchText"
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": api_key,
            # Request only Pro SKU fields (name + lat/lng) to avoid Enterprise billing.
            "X-Goog-FieldMask": "places.displayName,places.location",
        }

        try:
            response = await self._request(
                "POST",
                url,
                headers=headers,
                json_body={"textQuery": query, "maxResultCount": 1},
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Google Places lookup failed for '%s': %s", query, exc)
            return None

        places = payload.get("places") if isinstance(payload, dict) else None
        if not isinstance(places, list) or not places:
            return None

        top = places[0]
        location = top.get("location", {})
        try:
            lat = round(float(location["latitude"]), 6)
            lon = round(float(location["longitude"]), 6)
        except (KeyError, TypeError, ValueError):
            return None

        display = top.get("displayName", {})
        name = display.get("text", query) if isinstance(display, dict) else query
        return GeoLocation(
            latitude=lat,
            longitude=lon,
            display_name=str(name),
            provider="google_places",
        )

    async def geocode_place(
        self,
        query: str,
        *,
        viewbox: tuple[float, float, float, float] | None = None,
    ) -> GeoLocation | None:
        """Resolve a place name to coordinates, using local cache first."""
        cache_key = f"{query.strip().lower()}|{viewbox}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        match = await self._search_nominatim(query, viewbox=viewbox)
        if match is None and self._settings.google_places_api_key:
            match = await self._search_google_places(query)

        self._cache[cache_key] = match
        return match

    async def verify_activity(
        self,
        activity: ActivitySchema,
        *,
        destination: str,
        viewbox: tuple[float, float, float, float] | None = None,
    ) -> ActivitySchema:
        """Look up GPS coordinates for a single activity and return an updated copy."""
        place = extract_place_name(activity.title)
        candidates = [f"{place}, {destination}"]
        if place.lower() != destination.lower():
            candidates.append(place)

        match: GeoLocation | None = None
        for query in candidates:
            match = await self.geocode_place(query, viewbox=viewbox)
            if match is not None:
                break

        if match is None:
            return activity.model_copy(
                update={"latitude": None, "longitude": None, "verified": False}
            )

        return activity.model_copy(
            update={
                "latitude": match.latitude,
                "longitude": match.longitude,
                "verified": True,
            }
        )

    async def verify_itinerary(
        self, itinerary: TripItineraryResponseSchema
    ) -> TripItineraryResponseSchema:
        """Verify all activity locations and run same-day Haversine feasibility."""
        dest_loc = await self.geocode_place(itinerary.destination)
        dest_viewbox = dest_loc.boundingbox if dest_loc else None

        verified_days: list[DayPlanSchema] = []
        for day in itinerary.days:
            verified_activities: list[ActivitySchema] = []
            for act in day.activities:
                verified_act = await self.verify_activity(
                    act, destination=itinerary.destination, viewbox=dest_viewbox
                )
                verified_activities.append(verified_act)

            feasibility = evaluate_day_feasibility(
                verified_activities,
                max_leg_km=self._settings.max_same_day_distance_km,
                avg_speed_kmh=self._settings.average_travel_speed_kmh,
            )
            verified_days.append(
                day.model_copy(
                    update={
                        "activities": verified_activities,
                        "total_distance_km": feasibility.total_distance_km,
                        "feasible": feasibility.feasible,
                        "distance_warnings": feasibility.warnings,
                    }
                )
            )

        return itinerary.model_copy(update={"days": verified_days})


@lru_cache
def _build_geocoding_service() -> GeocodingService:
    return GeocodingService(get_settings())


def get_geocoding_service() -> GeocodingService:
    """FastAPI dependency (overridable with a mock in tests)."""
    return _build_geocoding_service()
