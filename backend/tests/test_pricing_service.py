"""Unit tests for the pluggable hybrid PricingService (zero live network calls)."""

import asyncio

import httpx
import pytest

from app.core.config import Settings
from app.models.response_schemas import PlaceOption
from app.services.pricing_service import (
    FreeWebSearchPricingProvider,
    MAX_SHORTLIST_DINING,
    MAX_SHORTLIST_HOTELS,
    PricingService,
    convert_currency,
    extract_verified_price_from_html,
)

pytestmark = pytest.mark.anyio


def _ddg_html(blocks: list[str]) -> str:
    body = "".join(
        f'<div class="result"><div class="result__body">{b}</div></div>' for b in blocks
    )
    return f"<html><body>{body}</body></html>"


@pytest.mark.parametrize(
    ("snippet", "place", "category", "target_currency", "expected_min", "expected_max"),
    [
        (
            "Pearl Continental Lahore rooms start from PKR 32,000 per night.",
            "Pearl Continental",
            "hotel",
            "PKR",
            31999.0,
            32001.0,
        ),
        (
            "Luxus Grand Hotel Lahore — Standard room $95 per night with breakfast.",
            "Luxus Grand Hotel",
            "hotel",
            "PKR",
            25000.0,
            28000.0,
        ),
        (
            "Haveli Restaurant menu price around Rs. 2,500 per person.",
            "Haveli Restaurant",
            "dining",
            "USD",
            8.0,
            10.0,
        ),
        (
            "Monal Cafe Islamabad avg dinner €20 per person.",
            "Monal Cafe",
            "dining",
            "EUR",
            19.5,
            20.5,
        ),
        (
            "Nishat Hotel Gulberg — nightly rate £80 or AED 350.",
            "Nishat Hotel",
            "hotel",
            "GBP",
            79.5,
            80.5,
        ),
        (
            "Serena Hotel stay from AED 450 per night.",
            "Serena Hotel",
            "hotel",
            "AED",
            449.0,
            451.0,
        ),
    ],
)
def test_extract_verified_price_supports_all_currencies(
    snippet, place, category, target_currency, expected_min, expected_max
):
    html_body = _ddg_html([f'<a class="result__a">{place}</a><p>{snippet}</p>'])
    res = extract_verified_price_from_html(
        html_body=html_body,
        place_name=place,
        category=category,
        target_currency=target_currency,
    )
    assert res.found is True
    assert res.price_source == "web_found"
    assert res.estimated_price is not None
    assert expected_min <= res.estimated_price <= expected_max
    assert "Web snippet rate" in res.price_note


def test_anti_hallucination_rejects_neighboring_hotel_price_and_bot_pages():
    # Snippet has a price, but ONLY for a different neighboring hotel!
    neighbor_html = _ddg_html(
        [
            "<a>Other Plaza Inn Lahore</a>"
            "<p>Rooms at Other Plaza Inn cost PKR 12,000.</p>",
            "<a>Pearl Continental Lahore</a>"
            "<p>Book luxury rooms in central Lahore.</p>",
        ]
    )
    res_neighbor = extract_verified_price_from_html(
        html_body=neighbor_html,
        place_name="Pearl Continental",
        category="hotel",
        target_currency="PKR",
    )
    assert res_neighbor.found is False
    assert res_neighbor.price_source == "ai_estimated"
    assert res_neighbor.estimated_price is None

    # Anti-bot / CAPTCHA HTML must return ai_estimated without extracting anything.
    bot_html = (
        '<div class="anomaly-modal">Please verify you are human. '
        "Pearl Continental PKR 20,000</div>"
    )
    res_bot = extract_verified_price_from_html(
        html_body=bot_html,
        place_name="Pearl Continental",
        category="hotel",
        target_currency="PKR",
    )
    assert res_bot.found is False
    assert res_bot.price_source == "ai_estimated"


def test_convert_currency_helpers():
    assert convert_currency(100.0, "USD", "USD") == 100.0
    assert convert_currency(100.0, "USD", "PKR") == 27850.0
    assert convert_currency(50.0, "ZZZ", "USD") == 50.0


async def test_free_web_pricing_provider_caches_and_handles_timeouts():
    call_count = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal call_count
        call_count += 1
        q = request.url.params.get("q", "")
        if "timeout hotel" in q.lower():
            raise httpx.ReadTimeout("slow search")
        if "blocked cafe" in q.lower():
            return httpx.Response(403, text="Forbidden")
        return httpx.Response(
            200,
            text=_ddg_html(
                ["<a>Faletti's Hotel</a><p>Faletti's Hotel rates PKR 18,500/night</p>"]
            ),
        )

    settings = Settings(pricing_timeout_seconds=1.0, pricing_cache_ttl_seconds=86400)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        provider = FreeWebSearchPricingProvider(settings=settings, http_client=http)

        first = await provider.lookup_place_price(
            "Faletti's Hotel", "Lahore", "hotel", "PKR"
        )
        second = await provider.lookup_place_price(
            "faletti's hotel", "lahore", "hotel", "PKR"
        )
        timed_out = await provider.lookup_place_price(
            "Timeout Hotel", "Lahore", "hotel", "PKR"
        )
        blocked = await provider.lookup_place_price(
            "Blocked Cafe", "Lahore", "dining", "PKR"
        )

    assert first.found is True
    assert first.price_source == "web_found"
    assert first.estimated_price == 18500.0
    assert second == first
    # 1 call for Faletti's (2nd hit cache) + 1 timeout + 1 blocked = 3
    assert call_count == 3
    assert timed_out.found is False and timed_out.price_source == "ai_estimated"
    assert blocked.found is False and blocked.price_source == "ai_estimated"


async def test_pricing_service_concurrency_shortlist_cap_and_enrichment():
    active = 0
    peak_concurrency = 0
    queried_names: list[str] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal active, peak_concurrency
        active += 1
        peak_concurrency = max(peak_concurrency, active)
        try:
            await asyncio.sleep(0.02)
            q = request.url.params.get("q", "")
            queried_names.append(q)
            if "Hotel 1" in q:
                return httpx.Response(
                    200,
                    text=_ddg_html(["<a>Hotel 1</a><p>Hotel 1 costs PKR 15,000</p>"]),
                )
            if "Cafe 1" in q:
                return httpx.Response(
                    200,
                    text=_ddg_html(["<a>Cafe 1</a><p>Cafe 1 meal Rs 1,200</p>"]),
                )
            return httpx.Response(200, text=_ddg_html(["<a>No price here</a>"]))
        finally:
            active -= 1

    hotels = [
        PlaceOption(
            option_id=f"hotel_{i:02d}",
            name=f"Hotel {i}",
            tier="mid_range",
            estimated_price=10000.0,
            total_estimated_cost=20000.0,
        )
        for i in range(1, 7)
    ]
    dining = [
        PlaceOption(
            option_id=f"dining_{i:02d}",
            name=f"Cafe {i}",
            tier="budget",
            estimated_price=1500.0,
            total_estimated_cost=1500.0,
        )
        for i in range(1, 9)
    ]

    settings = Settings(pricing_max_concurrency=4, pricing_timeout_seconds=2.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = PricingService.from_settings(settings, http_client=http)
        out_hotels, out_dining = await service.enrich_options(
            destination="Lahore, Pakistan",
            currency="PKR",
            duration_days=3,  # 2 nights
            hotel_options=hotels,
            dining_options=dining,
        )

    # Strictly caps lookups to MAX_SHORTLIST_HOTELS (4) + MAX_SHORTLIST_DINING (6) = 10
    assert len(queried_names) == MAX_SHORTLIST_HOTELS + MAX_SHORTLIST_DINING
    assert peak_concurrency <= 4

    # Hotel 1 upgraded to web_found and total recalculated for 2 nights
    assert out_hotels[0].price_source == "web_found"
    assert out_hotels[0].estimated_price == 15000.0
    assert out_hotels[0].total_estimated_cost == 30000.0
    # Unfound hotels stay honestly ai_estimated
    assert out_hotels[1].price_source == "ai_estimated"
    assert out_hotels[1].estimated_price == 10000.0

    # Cafe 1 upgraded to web_found; unfound dining stays ai_estimated
    assert out_dining[0].price_source == "web_found"
    assert out_dining[0].estimated_price == 1200.0
    assert out_dining[1].price_source == "ai_estimated"
