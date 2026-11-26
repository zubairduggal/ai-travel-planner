"""Real-Data-First POI discovery via OpenStreetMap Overpass API + Nominatim fallback.

Fetches real, named hotels/stays, restaurants/cafes, and tourist attractions with
exact GPS coordinates inside the destination's bounding box, deduplicates and
caps results, and caches them for 24 hours.
"""

from collections import OrderedDict
from functools import lru_cache
import logging
import time
from typing import Literal

import httpx
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.services.geocoding_service import (
    GeoLocation,
    GeocodingService,
    get_geocoding_service,
)
from app.utils.distance_calculator import haversine_km

logger = logging.getLogger(__name__)

MAX_HOTELS = 12
MAX_DINING = 15
MAX_ATTRACTIONS = 18
MIN_FALLBACK_THRESHOLD = 3
MAX_BBOX_HALF_SPAN_DEG = 0.45
MIN_BBOX_HALF_SPAN_DEG = 0.05

_HOTEL_TOURISM_VALUES = frozenset({"hotel", "guest_house", "hostel", "resort", "motel"})
_DINING_AMENITY_VALUES = frozenset({"restaurant", "cafe", "fast_food"})
_ATTRACTION_TOURISM_VALUES = frozenset(
    {"attraction", "museum", "viewpoint", "park", "gallery"}
)


class DiscoveredPOI(BaseModel):
    """A single real-world point of interest with verified OSM GPS coordinates."""

    name: str
    category: Literal["hotel", "dining", "attraction"]
    subcategory: str = ""
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    distance_to_center_km: float | None = Field(default=None, ge=0)
    source: Literal["overpass", "nominatim"] = "overpass"
    tags: dict[str, str] = Field(default_factory=dict)


class DestinationPOIBundle(BaseModel):
    """Deduplicated, capped POIs discovered for a travel destination."""

    destination: str
    center_lat: float | None = Field(default=None, ge=-90, le=90)
    center_lon: float | None = Field(default=None, ge=-180, le=180)
    hotels: list[DiscoveredPOI] = Field(default_factory=list)
    dining: list[DiscoveredPOI] = Field(default_factory=list)
    attractions: list[DiscoveredPOI] = Field(default_factory=list)
    source: Literal["overpass", "nominatim", "hybrid", "empty"] = "empty"


def _normalize_poi_name(name: str) -> str:
    return " ".join(name.strip().lower().split())


def _compute_search_bbox(
    location: GeoLocation,
) -> tuple[float, float, float, float]:
    """Build a bounded (south, west, north, east) Overpass bbox around location."""
    lat = location.latitude
    lon = location.longitude
    if location.boundingbox is not None:
        min_lat, max_lat, min_lon, max_lon = location.boundingbox
        south = max(min_lat, lat - MAX_BBOX_HALF_SPAN_DEG)
        north = min(max_lat, lat + MAX_BBOX_HALF_SPAN_DEG)
        west = max(min_lon, lon - MAX_BBOX_HALF_SPAN_DEG)
        east = min(max_lon, lon + MAX_BBOX_HALF_SPAN_DEG)
    else:
        south = lat - MIN_BBOX_HALF_SPAN_DEG
        north = lat + MIN_BBOX_HALF_SPAN_DEG
        west = lon - MIN_BBOX_HALF_SPAN_DEG
        east = lon + MIN_BBOX_HALF_SPAN_DEG

    if (north - south) < MIN_BBOX_HALF_SPAN_DEG * 2:
        south = lat - MIN_BBOX_HALF_SPAN_DEG
        north = lat + MIN_BBOX_HALF_SPAN_DEG
    if (east - west) < MIN_BBOX_HALF_SPAN_DEG * 2:
        west = lon - MIN_BBOX_HALF_SPAN_DEG
        east = lon + MIN_BBOX_HALF_SPAN_DEG

    south = max(-90.0, round(south, 5))
    north = min(90.0, round(north, 5))
    west = max(-180.0, round(west, 5))
    east = min(180.0, round(east, 5))
    return (south, west, north, east)


def build_overpass_query(bbox: tuple[float, float, float, float]) -> str:
    """Build a compact Overpass QL query for hotels, dining, and attractions."""
    s, w, n, e = bbox
    box = f"{s},{w},{n},{e}"
    hotel_re = "^(hotel|guest_house|hostel|resort|motel)$"
    dining_re = "^(restaurant|cafe|fast_food)$"
    attr_re = "^(attraction|museum|viewpoint|park|gallery)$"
    return (
        f"[out:json][timeout:10];\n"
        f"(\n"
        f'  nwr["tourism"~"{hotel_re}"]["name"]({box});\n'
        f'  nwr["amenity"~"{dining_re}"]["name"]({box});\n'
        f'  nwr["tourism"~"{attr_re}"]["name"]({box});\n'
        f'  nwr["historic"]["name"]({box});\n'
        f");\n"
        f"out center tags;"
    )


def _extract_coords(element: dict) -> tuple[float, float] | None:
    """Extract valid (lat, lon) from an Overpass node or way/relation center."""
    lat_raw = element.get("lat")
    lon_raw = element.get("lon")
    if lat_raw is None or lon_raw is None:
        center = element.get("center")
        if isinstance(center, dict):
            lat_raw = center.get("lat")
            lon_raw = center.get("lon")
    if lat_raw is None or lon_raw is None:
        return None
    try:
        lat = round(float(lat_raw), 6)
        lon = round(float(lon_raw), 6)
    except (TypeError, ValueError):
        return None
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        return None
    return (lat, lon)


def _classify_overpass_tags(
    tags: dict[str, object],
) -> tuple[Literal["hotel", "dining", "attraction"], str] | None:
    tourism = str(tags.get("tourism", "")).strip().lower()
    amenity = str(tags.get("amenity", "")).strip().lower()
    historic = str(tags.get("historic", "")).strip().lower()

    if tourism in _HOTEL_TOURISM_VALUES:
        return ("hotel", tourism)
    if amenity in _DINING_AMENITY_VALUES:
        return ("dining", amenity)
    if tourism in _ATTRACTION_TOURISM_VALUES:
        return ("attraction", tourism)
    if historic and historic not in {"no", "false"}:
        return ("attraction", f"historic:{historic}")
    return None


def _dedupe_and_cap(
    items: list[DiscoveredPOI],
    *,
    limit: int,
) -> list[DiscoveredPOI]:
    """Deduplicate POIs by normalized name, prefer Overpass & closer pins, and cap."""
    by_name: dict[str, DiscoveredPOI] = {}
    for item in items:
        key = _normalize_poi_name(item.name)
        if not key:
            continue
        existing = by_name.get(key)
        if existing is None:
            by_name[key] = item
            continue
        # Prefer Overpass over Nominatim; break ties by closer distance to center.
        existing_rank = (
            0 if existing.source == "overpass" else 1,
            (
                existing.distance_to_center_km
                if existing.distance_to_center_km is not None
                else 9999.0
            ),
        )
        new_rank = (
            0 if item.source == "overpass" else 1,
            (
                item.distance_to_center_km
                if item.distance_to_center_km is not None
                else 9999.0
            ),
        )
        if new_rank < existing_rank:
            by_name[key] = item

    sorted_items = sorted(
        by_name.values(),
        key=lambda p: (
            p.distance_to_center_km if p.distance_to_center_km is not None else 9999.0,
            p.name.lower(),
        ),
    )
    return sorted_items[:limit]


class POIDiscoveryService:
    """Discovers real named stays, dining, and attractions via Overpass + Nominatim."""

    def __init__(
        self,
        settings: Settings,
        geocoding_service: GeocodingService,
        http_client: httpx.AsyncClient | None = None,
        cache_max_entries: int = 500,
    ) -> None:
        self._settings = settings
        self._geocoder = geocoding_service
        self._http_client = http_client
        self._cache_max_entries = cache_max_entries
        self._cache: OrderedDict[str, tuple[DestinationPOIBundle, float | None]] = (
            OrderedDict()
        )

    def _get_cached(self, cache_key: str) -> DestinationPOIBundle | None:
        entry = self._cache.get(cache_key)
        if entry is None:
            return None
        bundle, expires_at = entry
        if expires_at is not None and time.monotonic() >= expires_at:
            self._cache.pop(cache_key, None)
            return None
        self._cache.move_to_end(cache_key)
        return bundle

    def _set_cached(self, cache_key: str, bundle: DestinationPOIBundle) -> None:
        ttl = self._settings.poi_cache_ttl_seconds
        expires_at = time.monotonic() + ttl if ttl > 0 else None
        self._cache[cache_key] = (bundle, expires_at)
        self._cache.move_to_end(cache_key)
        if len(self._cache) > self._cache_max_entries:
            self._cache.popitem(last=False)

    async def _post_overpass(self, query: str) -> dict | None:
        url = self._settings.overpass_base_url
        headers = {
            "User-Agent": self._settings.nominatim_user_agent,
            "Accept": "application/json",
        }
        try:
            if self._http_client is not None:
                resp = await self._http_client.post(
                    url,
                    data={"data": query},
                    headers=headers,
                    timeout=self._settings.overpass_timeout_seconds,
                    follow_redirects=False,
                )
            else:
                async with httpx.AsyncClient(
                    timeout=self._settings.overpass_timeout_seconds,
                    follow_redirects=False,
                ) as client:
                    resp = await client.post(url, data={"data": query}, headers=headers)
            resp.raise_for_status()
            payload = resp.json()
            return payload if isinstance(payload, dict) else None
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Overpass POI query failed: %s", exc)
            return None

    async def _nominatim_category_fallback(
        self,
        *,
        destination: str,
        category: Literal["hotel", "dining", "attraction"],
        center_lat: float,
        center_lon: float,
        bbox: tuple[float, float, float, float],
        limit: int,
    ) -> list[DiscoveredPOI]:
        """Fallback category search via Nominatim when Overpass is sparse or slow."""
        term_map = {
            "hotel": "hotel",
            "dining": "restaurant",
            "attraction": "tourist attraction",
        }
        south, west, north, east = bbox
        viewbox = f"{west},{south},{east},{north}"
        params: dict[str, str | int] = {
            "q": f"{term_map[category]} in {destination}",
            "format": "jsonv2",
            "limit": min(limit, 10),
            "viewbox": viewbox,
            "bounded": 1,
        }
        headers = {
            "User-Agent": self._settings.nominatim_user_agent,
            "Accept": "application/json",
        }
        url = f"{self._settings.nominatim_base_url.rstrip('/')}/search"

        await self._geocoder._throttle_nominatim()
        try:
            if self._http_client is not None:
                resp = await self._http_client.get(
                    url,
                    params=params,
                    headers=headers,
                    timeout=self._settings.geocoding_timeout_seconds,
                    follow_redirects=False,
                )
            else:
                async with httpx.AsyncClient(
                    timeout=self._settings.geocoding_timeout_seconds,
                    follow_redirects=False,
                ) as client:
                    resp = await client.get(url, params=params, headers=headers)
            resp.raise_for_status()
            rows = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning(
                "Nominatim fallback failed for %s (%s): %s", destination, category, exc
            )
            return []

        if not isinstance(rows, list):
            return []

        found: list[DiscoveredPOI] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            raw_name = str(row.get("name") or "").strip()
            if not raw_name:
                display = str(row.get("display_name") or "").strip()
                raw_name = display.split(",")[0].strip() if display else ""
            if not raw_name:
                continue
            try:
                lat = round(float(row["lat"]), 6)
                lon = round(float(row["lon"]), 6)
            except (KeyError, TypeError, ValueError):
                continue
            if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
                continue
            dist = haversine_km(center_lat, center_lon, lat, lon)
            found.append(
                DiscoveredPOI(
                    name=raw_name,
                    category=category,
                    subcategory=str(row.get("type") or term_map[category]),
                    latitude=lat,
                    longitude=lon,
                    distance_to_center_km=dist,
                    source="nominatim",
                )
            )
        return found

    def _parse_overpass_elements(
        self,
        elements: list[object],
        *,
        center_lat: float,
        center_lon: float,
    ) -> tuple[list[DiscoveredPOI], list[DiscoveredPOI], list[DiscoveredPOI]]:
        hotels: list[DiscoveredPOI] = []
        dining: list[DiscoveredPOI] = []
        attractions: list[DiscoveredPOI] = []

        for elem in elements:
            if not isinstance(elem, dict):
                continue
            tags = elem.get("tags")
            if not isinstance(tags, dict):
                continue
            name = str(tags.get("name") or "").strip()
            if not name:
                continue
            coords = _extract_coords(elem)
            if coords is None:
                continue
            classification = _classify_overpass_tags(tags)
            if classification is None:
                continue
            category, subcategory = classification
            lat, lon = coords
            dist = haversine_km(center_lat, center_lon, lat, lon)
            compact_tags = {
                k: str(v)
                for k, v in tags.items()
                if k in {"cuisine", "stars", "website", "tourism", "amenity"}
                and v is not None
            }
            poi = DiscoveredPOI(
                name=name,
                category=category,
                subcategory=subcategory,
                latitude=lat,
                longitude=lon,
                distance_to_center_km=dist,
                source="overpass",
                tags=compact_tags,
            )
            if category == "hotel":
                hotels.append(poi)
            elif category == "dining":
                dining.append(poi)
            else:
                attractions.append(poi)

        return hotels, dining, attractions

    async def discover_pois(self, destination: str) -> DestinationPOIBundle:
        """Discover real named hotels, dining, and attractions for a destination."""
        cleaned_dest = " ".join(destination.strip().split())
        cache_key = cleaned_dest.lower()
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        dest_loc = await self._geocoder.geocode_place(cleaned_dest)
        if dest_loc is None:
            return DestinationPOIBundle(destination=cleaned_dest, source="empty")

        bbox = _compute_search_bbox(dest_loc)
        ql_query = build_overpass_query(bbox)
        overpass_payload = await self._post_overpass(ql_query)

        overpass_hotels: list[DiscoveredPOI] = []
        overpass_dining: list[DiscoveredPOI] = []
        overpass_attractions: list[DiscoveredPOI] = []
        used_overpass = False

        if overpass_payload and isinstance(overpass_payload.get("elements"), list):
            overpass_hotels, overpass_dining, overpass_attractions = (
                self._parse_overpass_elements(
                    overpass_payload["elements"],
                    center_lat=dest_loc.latitude,
                    center_lon=dest_loc.longitude,
                )
            )
            used_overpass = bool(
                overpass_hotels or overpass_dining or overpass_attractions
            )

        hotels = list(overpass_hotels)
        dining = list(overpass_dining)
        attractions = list(overpass_attractions)
        used_nominatim = False

        # Trigger graceful Nominatim fallback for any sparse/empty bucket.
        if len(hotels) < MIN_FALLBACK_THRESHOLD:
            fb = await self._nominatim_category_fallback(
                destination=cleaned_dest,
                category="hotel",
                center_lat=dest_loc.latitude,
                center_lon=dest_loc.longitude,
                bbox=bbox,
                limit=MAX_HOTELS,
            )
            if fb:
                used_nominatim = True
                hotels.extend(fb)

        if len(dining) < MIN_FALLBACK_THRESHOLD:
            fb = await self._nominatim_category_fallback(
                destination=cleaned_dest,
                category="dining",
                center_lat=dest_loc.latitude,
                center_lon=dest_loc.longitude,
                bbox=bbox,
                limit=MAX_DINING,
            )
            if fb:
                used_nominatim = True
                dining.extend(fb)

        if len(attractions) < MIN_FALLBACK_THRESHOLD:
            fb = await self._nominatim_category_fallback(
                destination=cleaned_dest,
                category="attraction",
                center_lat=dest_loc.latitude,
                center_lon=dest_loc.longitude,
                bbox=bbox,
                limit=MAX_ATTRACTIONS,
            )
            if fb:
                used_nominatim = True
                attractions.extend(fb)

        final_hotels = _dedupe_and_cap(hotels, limit=MAX_HOTELS)
        final_dining = _dedupe_and_cap(dining, limit=MAX_DINING)
        final_attractions = _dedupe_and_cap(attractions, limit=MAX_ATTRACTIONS)

        if used_overpass and used_nominatim:
            source: Literal["overpass", "nominatim", "hybrid", "empty"] = "hybrid"
        elif used_overpass:
            source = "overpass"
        elif used_nominatim:
            source = "nominatim"
        else:
            source = "empty"

        bundle = DestinationPOIBundle(
            destination=cleaned_dest,
            center_lat=dest_loc.latitude,
            center_lon=dest_loc.longitude,
            hotels=final_hotels,
            dining=final_dining,
            attractions=final_attractions,
            source=source,
        )
        self._set_cached(cache_key, bundle)
        return bundle


@lru_cache
def _build_poi_discovery_service() -> POIDiscoveryService:
    return POIDiscoveryService(
        settings=get_settings(),
        geocoding_service=get_geocoding_service(),
    )


def get_poi_discovery_service() -> POIDiscoveryService:
    """FastAPI dependency (overridable with a mock in tests)."""
    return _build_poi_discovery_service()
