"""Pluggable hybrid pricing engine for real hotel & dining options.

Architecture:
- `BasePricingProvider` defines a clean interface so commercial APIs
  (Amadeus, Booking, Google Places) can be swapped in via configuration.
- `FreeWebSearchPricingProvider` queries public web search HTML snippets
  concurrently (`asyncio.Semaphore(4)`, 4.0s timeout, 24h cache) ONLY on
  shortlisted hotels (max 4) and restaurants (max 6).
- Strict anti-hallucination rule: a price is marked `web_found` ONLY when
  an explicit currency+number appears inside a search result block whose
  title/snippet ties directly to that exact place name. Otherwise returns
  `found=False` so callers keep `price_source="ai_estimated"`.
"""

from abc import ABC, abstractmethod
import asyncio
from collections import OrderedDict
from functools import lru_cache
import html
import logging
import re
import time
from typing import Literal

import httpx
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.models.response_schemas import PlaceOption

logger = logging.getLogger(__name__)

MAX_SHORTLIST_HOTELS = 4
MAX_SHORTLIST_DINING = 6

# Static USD pivot rates used solely to normalize extracted web prices.
_USD_RATES: dict[str, float] = {
    "USD": 1.0,
    "PKR": 278.5,
    "EUR": 0.92,
    "GBP": 0.79,
    "AED": 3.673,
}

# Reasonable sanity bounds in USD to reject years, phone numbers, or noise.
_HOTEL_USD_BOUNDS = (5.0, 2500.0)
_DINING_USD_BOUNDS = (1.0, 350.0)

_STOP_WORDS = frozenset(
    {
        "hotel",
        "hotels",
        "resort",
        "inn",
        "guest",
        "house",
        "hostel",
        "motel",
        "restaurant",
        "cafe",
        "coffee",
        "kitchen",
        "the",
        "and",
        "lahore",
        "islamabad",
        "karachi",
        "pakistan",
    }
)

# Explicit currency+price regex patterns (prefix and suffix forms).
_NUM_PKR = r"((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{2,6})(?:\.[0-9]{1,2})?)"
_NUM_STD = r"((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,5})(?:\.[0-9]{1,2})?)"

_PRICE_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("PKR", re.compile(rf"(?:\bPKR\b|\bRs\.?)\s*{_NUM_PKR}", re.IGNORECASE)),
    ("PKR", re.compile(rf"\b{_NUM_PKR}\s*(?:PKR|Rs\.?)\b", re.IGNORECASE)),
    ("USD", re.compile(rf"(?:US\$|\$|\bUSD\b)\s*{_NUM_STD}", re.IGNORECASE)),
    ("USD", re.compile(rf"\b{_NUM_STD}\s*USD\b", re.IGNORECASE)),
    ("EUR", re.compile(rf"(?:€|\bEUR\b)\s*{_NUM_STD}", re.IGNORECASE)),
    ("GBP", re.compile(rf"(?:£|\bGBP\b)\s*{_NUM_STD}", re.IGNORECASE)),
    ("AED", re.compile(rf"(?:\bAED\b)\s*{_NUM_STD}", re.IGNORECASE)),
    ("AED", re.compile(rf"\b{_NUM_STD}\s*AED\b", re.IGNORECASE)),
)

_HTML_TAG_RE = re.compile(r"<[^>]+>")
_RESULT_BLOCK_RE = re.compile(
    r'<div[^>]+class="[^"]*result__body[^"]*"[^>]*>(.*?)</div>\s*</div>',
    re.IGNORECASE | re.DOTALL,
)
_BOT_BLOCK_MARKERS = ("anomaly-modal", "bot detection", "captcha", "verify you are")


class PriceLookupResult(BaseModel):
    """Outcome of a single place price lookup."""

    found: bool = False
    estimated_price: float | None = Field(default=None, ge=0)
    currency: str = "USD"
    price_source: Literal["web_found", "ai_estimated"] = "ai_estimated"
    price_note: str = ""


def convert_currency(amount: float, from_currency: str, to_currency: str) -> float:
    """Convert an amount between supported currencies via USD pivot."""
    src = from_currency.upper()
    dst = to_currency.upper()
    if src == dst:
        return round(amount, 2)
    src_rate = _USD_RATES.get(src)
    dst_rate = _USD_RATES.get(dst)
    if not src_rate or not dst_rate:
        return round(amount, 2)
    usd = amount / src_rate
    converted = usd * dst_rate
    if dst == "PKR" and converted >= 100:
        return float(round(converted))
    return round(converted, 2)


def _strip_html(raw: str) -> str:
    text = _HTML_TAG_RE.sub(" ", raw)
    text = html.unescape(text)
    return " ".join(text.split())


def _place_matches_text(place_name: str, text: str) -> bool:
    """Verify the snippet explicitly refers to this exact place, not a neighbor."""
    norm_place = re.sub(r"[^a-z0-9\s]", " ", place_name.lower())
    norm_place = " ".join(norm_place.split())
    norm_text = re.sub(r"[^a-z0-9\s]", " ", text.lower())
    norm_text = " ".join(norm_text.split())
    if not norm_place or not norm_text:
        return False
    if norm_place in norm_text:
        return True
    tokens = [
        tok for tok in norm_place.split() if len(tok) >= 3 and tok not in _STOP_WORDS
    ]
    if not tokens:
        tokens = [tok for tok in norm_place.split() if len(tok) >= 2]
    if not tokens:
        return False
    return all(re.search(rf"\b{re.escape(tok)}\b", norm_text) for tok in tokens)


def extract_verified_price_from_html(
    *,
    html_body: str,
    place_name: str,
    category: Literal["hotel", "dining"],
    target_currency: str,
) -> PriceLookupResult:
    """Extract an explicit numeric price ONLY from a block tied to `place_name`."""
    lower_body = html_body.lower()
    if any(marker in lower_body for marker in _BOT_BLOCK_MARKERS):
        return PriceLookupResult(
            found=False, currency=target_currency.upper(), price_source="ai_estimated"
        )

    raw_blocks = _RESULT_BLOCK_RE.findall(html_body)
    blocks = [_strip_html(b) for b in raw_blocks] if raw_blocks else []
    if not blocks:
        # Support simplified/plain snippet HTML in unit tests or alternate markup.
        stripped = _strip_html(html_body)
        if stripped:
            blocks = [stripped]

    min_usd, max_usd = _HOTEL_USD_BOUNDS if category == "hotel" else _DINING_USD_BOUNDS
    target = target_currency.upper()

    for block in blocks:
        if not _place_matches_text(place_name, block):
            continue
        for src_currency, pattern in _PRICE_PATTERNS:
            for match in pattern.finditer(block):
                num_str = match.group(1).replace(",", "")
                try:
                    raw_amount = float(num_str)
                except ValueError:
                    continue
                usd_equiv = convert_currency(raw_amount, src_currency, "USD")
                if not (min_usd <= usd_equiv <= max_usd):
                    continue
                converted = convert_currency(raw_amount, src_currency, target)
                unit = "night" if category == "hotel" else "meal"
                note = f"Web snippet rate (~{src_currency} {raw_amount:g}/{unit})"
                return PriceLookupResult(
                    found=True,
                    estimated_price=converted,
                    currency=target,
                    price_source="web_found",
                    price_note=note,
                )

    return PriceLookupResult(found=False, currency=target, price_source="ai_estimated")


class BasePricingProvider(ABC):
    """Pluggable contract for free or commercial place pricing providers."""

    @abstractmethod
    async def lookup_place_price(
        self,
        place_name: str,
        city: str,
        category: Literal["hotel", "dining"],
        currency: str,
    ) -> PriceLookupResult:
        """Look up a verified price for a single named place."""


class DisabledPricingProvider(BasePricingProvider):
    """No-op provider for offline tests or when web pricing is disabled."""

    async def lookup_place_price(
        self,
        place_name: str,
        city: str,
        category: Literal["hotel", "dining"],
        currency: str,
    ) -> PriceLookupResult:
        return PriceLookupResult(
            found=False, currency=currency.upper(), price_source="ai_estimated"
        )


class FreeWebSearchPricingProvider(BasePricingProvider):
    """Queries public DuckDuckGo HTML snippets with concurrency cap and 24h cache."""

    def __init__(
        self,
        settings: Settings,
        http_client: httpx.AsyncClient | None = None,
        cache_max_entries: int = 1000,
    ) -> None:
        self._settings = settings
        self._http_client = http_client
        self._semaphore = asyncio.Semaphore(settings.pricing_max_concurrency)
        self._cache_max_entries = cache_max_entries
        self._cache: OrderedDict[str, tuple[PriceLookupResult, float | None]] = (
            OrderedDict()
        )

    def _get_cached(self, key: str) -> PriceLookupResult | None:
        entry = self._cache.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at is not None and time.monotonic() >= expires_at:
            self._cache.pop(key, None)
            return None
        self._cache.move_to_end(key)
        return value

    def _set_cached(self, key: str, value: PriceLookupResult) -> None:
        ttl = self._settings.pricing_cache_ttl_seconds
        expires_at = time.monotonic() + ttl if ttl > 0 else None
        self._cache[key] = (value, expires_at)
        self._cache.move_to_end(key)
        if len(self._cache) > self._cache_max_entries:
            self._cache.popitem(last=False)

    async def lookup_place_price(
        self,
        place_name: str,
        city: str,
        category: Literal["hotel", "dining"],
        currency: str,
    ) -> PriceLookupResult:
        target_currency = currency.upper()
        cache_key = (
            f"{place_name.strip().lower()}|{city.strip().lower()}|"
            f"{category}|{target_currency}"
        )
        cached = self._get_cached(cache_key)
        if cached is not None:
            return cached

        suffix = "room price" if category == "hotel" else "menu price"
        query = f'"{place_name.strip()}" {city.strip()} {suffix}'
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/128.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml",
        }

        async with self._semaphore:
            try:
                if self._http_client is not None:
                    resp = await asyncio.wait_for(
                        self._http_client.get(
                            self._settings.pricing_search_url,
                            params={"q": query},
                            headers=headers,
                            timeout=self._settings.pricing_timeout_seconds,
                            follow_redirects=False,
                        ),
                        timeout=self._settings.pricing_timeout_seconds,
                    )
                else:
                    async with httpx.AsyncClient(
                        timeout=self._settings.pricing_timeout_seconds,
                        follow_redirects=False,
                    ) as client:
                        resp = await asyncio.wait_for(
                            client.get(
                                self._settings.pricing_search_url,
                                params={"q": query},
                                headers=headers,
                            ),
                            timeout=self._settings.pricing_timeout_seconds,
                        )
            except (asyncio.TimeoutError, httpx.HTTPError) as exc:
                logger.debug("Pricing search failed for '%s': %s", place_name, exc)
                return PriceLookupResult(
                    found=False, currency=target_currency, price_source="ai_estimated"
                )

        if resp.status_code != 200:
            return PriceLookupResult(
                found=False, currency=target_currency, price_source="ai_estimated"
            )

        result = extract_verified_price_from_html(
            html_body=resp.text,
            place_name=place_name,
            category=category,
            target_currency=target_currency,
        )
        self._set_cached(cache_key, result)
        return result


class PricingService:
    """Enriches shortlisted hotel & dining PlaceOptions via a BasePricingProvider."""

    def __init__(self, provider: BasePricingProvider) -> None:
        self._provider = provider

    @classmethod
    def from_settings(
        cls,
        settings: Settings,
        http_client: httpx.AsyncClient | None = None,
    ) -> "PricingService":
        if settings.pricing_provider == "disabled":
            return cls(DisabledPricingProvider())
        return cls(
            FreeWebSearchPricingProvider(settings=settings, http_client=http_client)
        )

    async def enrich_options(
        self,
        *,
        destination: str,
        currency: str,
        duration_days: int,
        hotel_options: list[PlaceOption],
        dining_options: list[PlaceOption],
    ) -> tuple[list[PlaceOption], list[PlaceOption]]:
        """Concurrently look up shortlisted hotel (max 4) & dining (max 6) rates."""
        city = destination.split(",")[0].strip() or destination.strip()
        nights = max(1, duration_days - 1) if duration_days > 1 else 1

        shortlist_hotels = hotel_options[:MAX_SHORTLIST_HOTELS]
        shortlist_dining = dining_options[:MAX_SHORTLIST_DINING]

        hotel_tasks = [
            self._provider.lookup_place_price(opt.name, city, "hotel", currency)
            for opt in shortlist_hotels
        ]
        dining_tasks = [
            self._provider.lookup_place_price(opt.name, city, "dining", currency)
            for opt in shortlist_dining
        ]

        all_results = await asyncio.gather(
            *(hotel_tasks + dining_tasks), return_exceptions=True
        )
        hotel_results = all_results[: len(shortlist_hotels)]
        dining_results = all_results[len(shortlist_hotels) :]

        enriched_hotels: list[PlaceOption] = []
        for idx, opt in enumerate(hotel_options):
            res = hotel_results[idx] if idx < len(hotel_results) else None
            if (
                isinstance(res, PriceLookupResult)
                and res.found
                and res.estimated_price is not None
            ):
                enriched_hotels.append(
                    opt.model_copy(
                        update={
                            "estimated_price": res.estimated_price,
                            "total_estimated_cost": round(
                                res.estimated_price * nights, 2
                            ),
                            "price_source": "web_found",
                            "price_note": res.price_note,
                        }
                    )
                )
            else:
                enriched_hotels.append(
                    opt.model_copy(update={"price_source": "ai_estimated"})
                )

        enriched_dining: list[PlaceOption] = []
        for idx, opt in enumerate(dining_options):
            res = dining_results[idx] if idx < len(dining_results) else None
            if (
                isinstance(res, PriceLookupResult)
                and res.found
                and res.estimated_price is not None
            ):
                enriched_dining.append(
                    opt.model_copy(
                        update={
                            "estimated_price": res.estimated_price,
                            "total_estimated_cost": round(res.estimated_price, 2),
                            "price_source": "web_found",
                            "price_note": res.price_note,
                        }
                    )
                )
            else:
                enriched_dining.append(
                    opt.model_copy(update={"price_source": "ai_estimated"})
                )

        return enriched_hotels, enriched_dining


@lru_cache
def _build_pricing_service() -> PricingService:
    return PricingService.from_settings(get_settings())


def get_pricing_service() -> PricingService:
    """FastAPI dependency (overridable with a mock in tests)."""
    return _build_pricing_service()
