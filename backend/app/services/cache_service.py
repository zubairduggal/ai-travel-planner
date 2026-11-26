"""Response caching service supporting DiskCache (dev) and Redis (prod) (M4).

DiskCache is synchronous/SQLite-backed, so all DiskCache calls are offloaded
with `asyncio.to_thread(...)` to avoid blocking FastAPI's event loop.
Redis uses `redis.asyncio` natively for non-blocking distributed caching.
"""

import asyncio
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import logging
import time
from abc import ABC, abstractmethod
from functools import lru_cache
from typing import Any

import diskcache
from pydantic import ValidationError
from redis import asyncio as redis_async

from app.core.config import Settings, get_settings
from app.models.request_schemas import TripRequestSchema
from app.models.response_schemas import TripItineraryResponseSchema

logger = logging.getLogger(__name__)


def build_itinerary_cache_key(trip: TripRequestSchema) -> str:
    """Build a deterministic, normalized cache key for a trip request."""
    normalized_destination = " ".join(trip.destination.strip().lower().split())
    normalized_departure = (
        " ".join(trip.departure_city.strip().lower().split())
        if trip.departure_city
        else None
    )
    canonical = {
        "destination": normalized_destination,
        "start_date": trip.start_date.isoformat(),
        "end_date": trip.end_date.isoformat(),
        "budget": round(trip.budget, 2),
        "currency": trip.currency.upper(),
        "interests": sorted(item.strip().lower() for item in trip.interests),
        "travel_style": trip.travel_style.strip().lower(),
        "travel_mode": trip.travel_mode.strip().lower(),
        "departure_city": normalized_departure,
    }
    raw = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return f"itinerary:{digest}"


class CacheBackend(ABC):
    """Async interface implemented by DiskCache, Redis, and Memory backends."""

    @abstractmethod
    async def get(self, key: str) -> str | None:
        """Return cached string value or None on miss."""

    @abstractmethod
    async def set(self, key: str, value: str, ttl_seconds: int) -> None:
        """Store a string value with optional TTL (0 = no expiration)."""

    @abstractmethod
    async def delete(self, key: str) -> None:
        """Remove a single key."""

    @abstractmethod
    async def clear(self) -> None:
        """Remove all keys in this cache."""

    async def close(self) -> None:
        """Release underlying connections/handles if any."""


class MemoryCacheBackend(CacheBackend):
    """In-memory async cache with TTL support (ideal for isolated unit tests)."""

    def __init__(self) -> None:
        self._store: dict[str, tuple[str, float | None]] = {}

    async def get(self, key: str) -> str | None:
        entry = self._store.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at is not None and time.monotonic() >= expires_at:
            self._store.pop(key, None)
            return None
        return value

    async def set(self, key: str, value: str, ttl_seconds: int) -> None:
        expires_at = time.monotonic() + ttl_seconds if ttl_seconds > 0 else None
        self._store[key] = (value, expires_at)

    async def delete(self, key: str) -> None:
        self._store.pop(key, None)

    async def clear(self) -> None:
        self._store.clear()


class _NoPickleDisk(diskcache.Disk):
    """DiskCache serializer that disables pickle to mitigate CVE-2025-69872."""

    def store(self, value: Any, read: bool, key: Any = diskcache.UNKNOWN) -> Any:
        if not isinstance(value, (str, bytes, int, float)) and value is not None:
            raise ValueError("Only JSON text or primitive values may be cached")
        return super().store(value, read, key=key)

    def fetch(self, mode: int, filename: Any, value: Any, read: bool) -> Any:
        if mode == diskcache.core.MODE_PICKLE:
            raise ValueError("Pickle deserialization is disabled for security")
        return super().fetch(mode, filename, value, read)


class DiskCacheBackend(CacheBackend):
    """SQLite-backed local DiskCache running on a dedicated single worker thread.

    Using a single-thread executor ensures DiskCache's thread-local SQLite
    connection is reused across calls and cleanly closed on shutdown.
    """

    def __init__(self, directory: str) -> None:
        self._directory = directory
        self._cache: diskcache.Cache | None = None
        self._executor = ThreadPoolExecutor(
            max_workers=1, thread_name_prefix="diskcache"
        )

    def _ensure_cache(self) -> diskcache.Cache:
        if self._cache is None:
            self._cache = diskcache.Cache(self._directory, disk=_NoPickleDisk)
        return self._cache

    async def _run(self, fn: Any, *args: Any, **kwargs: Any) -> Any:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(self._executor, lambda: fn(*args, **kwargs))

    async def get(self, key: str) -> str | None:
        try:
            value = await self._run(lambda: self._ensure_cache().get(key))
        except ValueError as exc:
            logger.warning("Rejected unsafe DiskCache entry for %s: %s", key, exc)
            return None
        return value if isinstance(value, str) else None

    async def set(self, key: str, value: str, ttl_seconds: int) -> None:
        expire = ttl_seconds if ttl_seconds > 0 else None
        await self._run(lambda: self._ensure_cache().set(key, value, expire=expire))

    async def delete(self, key: str) -> None:
        await self._run(lambda: self._ensure_cache().delete(key))

    async def clear(self) -> None:
        await self._run(lambda: self._ensure_cache().clear())

    async def close(self) -> None:
        def _close() -> None:
            if self._cache is not None:
                self._cache.close()
                self._cache = None

        try:
            await self._run(_close)
        finally:
            self._executor.shutdown(wait=True)


class RedisCacheBackend(CacheBackend):
    """Distributed async Redis cache using `redis.asyncio`."""

    def __init__(self, redis_url: str, client: Any | None = None) -> None:
        self._client = (
            client
            if client is not None
            else redis_async.from_url(redis_url, decode_responses=True)
        )

    async def get(self, key: str) -> str | None:
        try:
            value = await self._client.get(key)
            return value if isinstance(value, str) else None
        except Exception as exc:
            logger.warning("Redis GET failed for key %s: %s", key, exc)
            return None

    async def set(self, key: str, value: str, ttl_seconds: int) -> None:
        try:
            if ttl_seconds > 0:
                await self._client.set(key, value, ex=ttl_seconds)
            else:
                await self._client.set(key, value)
        except Exception as exc:
            logger.warning("Redis SET failed for key %s: %s", key, exc)

    async def delete(self, key: str) -> None:
        try:
            await self._client.delete(key)
        except Exception as exc:
            logger.warning("Redis DELETE failed for key %s: %s", key, exc)

    async def clear(self) -> None:
        try:
            await self._client.flushdb()
        except Exception as exc:
            logger.warning("Redis CLEAR failed: %s", exc)

    async def close(self) -> None:
        try:
            await self._client.aclose()
        except Exception as exc:
            logger.warning("Redis CLOSE failed: %s", exc)


class CacheService:
    """High-level typed cache wrapper for itinerary responses."""

    def __init__(self, backend: CacheBackend, ttl_seconds: int = 86400) -> None:
        self._backend = backend
        self._ttl_seconds = ttl_seconds

    @classmethod
    def from_settings(cls, settings: Settings) -> "CacheService":
        if settings.cache_backend == "redis":
            backend: CacheBackend = RedisCacheBackend(settings.redis_url)
        elif settings.cache_backend == "memory":
            backend = MemoryCacheBackend()
        else:
            backend = DiskCacheBackend(settings.diskcache_dir)
        return cls(backend=backend, ttl_seconds=settings.cache_ttl_seconds)

    async def get_itinerary(
        self, trip: TripRequestSchema
    ) -> TripItineraryResponseSchema | None:
        key = build_itinerary_cache_key(trip)
        raw = await self._backend.get(key)
        if raw is None:
            return None
        try:
            return TripItineraryResponseSchema.model_validate_json(raw)
        except ValidationError as exc:
            logger.warning("Corrupted cached itinerary for %s: %s", key, exc)
            await self._backend.delete(key)
            return None

    async def set_itinerary(
        self, trip: TripRequestSchema, itinerary: TripItineraryResponseSchema
    ) -> None:
        key = build_itinerary_cache_key(trip)
        await self._backend.set(key, itinerary.model_dump_json(), self._ttl_seconds)

    async def clear(self) -> None:
        await self._backend.clear()

    async def close(self) -> None:
        await self._backend.close()


@lru_cache
def _build_cache_service() -> CacheService:
    return CacheService.from_settings(get_settings())


def get_cache_service() -> CacheService:
    """FastAPI dependency (overridable in tests)."""
    return _build_cache_service()
