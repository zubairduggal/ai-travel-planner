# Backend Development & Testing Reports

## Milestone Execution Summary

| Milestone | Status | Test Coverage | GitHub Commit Hash | Date Completed |
| :--- | :--- | :--- | :--- | :--- |
| **M1: Core API Setup** | Completed | Not measured (`pytest-cov` is added in M5); 18/18 tests passed | `3b142a8` | 2026-11-23 |
| **M2: AI Itinerary Engine** | Completed | 99% (34 passed, 1 live skipped) | `0ea88ae` | 2026-11-23 |
| **M3: Geocoding & Verification**| Completed | 97% (54 passed, 1 live passed) | `ac6061f` | 2026-11-23 |
| **M4: Caching & Rate Limit** | Completed | 97% (64 passed, 2 live skipped) | `cfa8744` | 2026-11-23 |
| **M5: Docker & Production** | Completed | 97.03% (64 passed, `black=0`, `flake8=0`) | `b389429` | 2026-11-23 |

---

## Milestone 1 (M1) Report
- **Date:** 2026-11-23
- **Environment:** Windows, Python 3.11.9, virtual env at `backend/.venv`
- **Features Completed:**
  - Project structure initialized per PRD Section 3 (M1 files only; later-milestone files are created in their milestones).
  - `app/core/config.py`: `pydantic-settings` `Settings` loading `.env` (`APP_NAME`, `APP_VERSION`, `APP_ENV`, `DEBUG`, `API_V1_PREFIX`), served through cached `get_settings()`.
  - `app/models/request_schemas.py`: `TripRequestSchema` (PRD 4.1) with validation: `end_date >= start_date`, `budget > 0`, 3-letter currency code (upper-cased), at least one non-empty interest, inclusive `duration_days`.
  - `app/models/response_schemas.py`: `ActivitySchema`, `DayPlanSchema`, `TripItineraryResponseSchema` (PRD 4.1), `HealthResponseSchema`.
  - `GET /api/v1/health` returning `status`, `timestamp` (UTC ISO-8601) and `environment`.
  - `app/main.py`: FastAPI app factory, CORS middleware, v1 router, Swagger `/docs` and ReDoc `/redoc`.
- **Installed versions (pinned in `requirements.txt`):** fastapi 0.165.0, uvicorn 0.54.0, pydantic 2.14.4, pydantic-settings 2.16.3, python-dotenv 1.2.4, pytest 9.2.0, httpx 0.28.1
- **Pytest Output:** (`pytest tests/test_health.py -v`)
  ```text
  tests/test_health.py::test_health_check_returns_200 PASSED
  tests/test_health.py::test_unknown_route_returns_404 PASSED
  tests/test_health.py::test_openapi_docs_available PASSED
  tests/test_health.py::test_trip_request_accepts_prd_example PASSED
  tests/test_health.py::test_trip_request_normalises_currency_case PASSED
  tests/test_health.py::test_trip_request_rejects_invalid_input[override0..8] PASSED (9 cases)
  tests/test_health.py::test_trip_request_requires_all_fields PASSED
  tests/test_health.py::test_response_schema_accepts_prd_sample PASSED
  tests/test_health.py::test_activity_defaults_to_unverified_without_coordinates PASSED
  tests/test_health.py::test_response_schema_rejects_out_of_range_latitude PASSED
  ============================= 18 passed in 0.15s ==============================
  ```
- **Notes / Observations:**
  - `latitude` / `longitude` are optional (`null`) and `verified` defaults to `false` until the M3 geocoding service fills them. The PRD sample response still validates.
  - `travel_style` is accepted as free text, because the PRD only shows `"Moderate"` and does not list allowed values.
  - Committed and pushed to https://github.com/zubairduggal/ai-travel-planner (`main`, commit `3b142a8`, message `feat: complete milestone M1`).
  - Ready for Gemini API integration (M2).

---

## Milestone 2 (M2) Report
- **Date:** 2026-11-23
- **Features Completed:**
  - `app/utils/prompt_templates.py`: System instruction and user prompt builder enforcing real named places, realistic same-day proximity, time slots (`Morning`/`Afternoon`/`Evening`), and budget compliance.
  - `app/services/ai_engine.py`: Async Google Gemini integration (`google-genai==3.6.1`, `client.aio.models.generate_content`) using structured JSON output (`response_mime_type="application/json"`, `response_schema=LLMItinerary`), timeout enforcement (`HttpOptions.timeout` + `asyncio.wait_for`), retry on malformed JSON, server-side `trip_id`/`activity_id` assignment, day sorting, and cost reconciliation.
  - `app/core/exceptions.py`: Standardized JSON error envelope (`{"error": {"code": ..., "message": ...}}`) handling missing API key (`503`), invalid API key (`503`), Gemini quota/429 (`503`), timeouts (`504`), provider errors (`502`), and invalid/malformed responses (`502`).
  - `app/api/v1/endpoints/itinerary.py`: `POST /api/v1/itinerary/generate` wired with FastAPI dependency injection (`Depends(get_ai_engine)`).
  - `tests/test_itinerary_api.py`: 17 tests covering happy path, day sorting, retry-on-malformed-JSON, every error mapping, request validation (`422`), and an opt-in `@pytest.mark.live` test.
- **Installed versions added to `requirements.txt`:** `google-genai==3.6.1`, `pytest-cov==7.1.0`
- **Sample API Response (`POST /api/v1/itinerary/generate`):**
  ```json
  {
    "trip_id": "itinerary_9f8a2b1c",
    "destination": "Hunza Valley, Pakistan",
    "duration_days": 2,
    "total_estimated_cost": 80.5,
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
            "description": "Explore the 700-year-old historic fort overlooking the valley.",
            "category": "Historical",
            "estimated_cost": 15.0,
            "latitude": null,
            "longitude": null,
            "verified": false
          }
        ]
      }
    ]
  }
  ```
- **Pytest & Coverage Output:** (`pytest --cov=app --cov-report=term-missing -v`)
  ```text
  tests/test_health.py (18 passed)
  tests/test_itinerary_api.py (16 passed, 1 skipped [live test requires RUN_LIVE_TESTS=1 + GEMINI_API_KEY])
  TOTAL: 268 statements, 1 missed, 99% coverage
  ======================== 34 passed, 1 skipped in 0.51s ========================
  ```
- **Notes / Observations:**
  - Verified against installed `google-genai==3.6.1` API directly; default model set to `gemini-3.8-flash` (configurable via `GEMINI_MODEL` in `.env`).
  - `latitude`/`longitude` remain `null` and `verified` stays `false` until M3 geocoding populates them.
  - Ready for Geocoding & Location Verification Service (M3).

---

## Milestone 3 (M3) Report
- **Date:** 2026-11-23
- **Features Completed:**
  - `app/utils/distance_calculator.py`: Haversine great-circle distance calculator (`EARTH_RADIUS_KM = 6371.0088`), travel time estimator, and `evaluate_day_feasibility(...)` flagging consecutive verified legs exceeding `MAX_SAME_DAY_DISTANCE_KM` (default `50 km`).
  - `app/services/geocoding_service.py`: OpenStreetMap Nominatim (`/search?format=jsonv2&limit=1`) location verification with custom `User-Agent`, global async 1 req/sec rate-limit throttle (`nominatim_min_interval_seconds = 1.05`), local query cache, activity title cleaning (`extract_place_name`), destination `viewbox` biasing, and optional Google Places API (New) fallback (`X-Goog-FieldMask: places.displayName,places.location`).
  - Integrated geocoding + same-day Haversine feasibility directly into `POST /api/v1/itinerary/generate` (`latitude`, `longitude`, `verified` on activities; `total_distance_km`, `feasible`, `distance_warnings` on days).
  - `app/api/v1/endpoints/weather.py`: `GET /api/v1/weather` proxy powered by Open-Meteo (no API key required) with WMO weather condition descriptions and timeout/upstream error handling (`504`/`502`).
  - `tests/test_geocoding.py`: 21 tests (20 unit/mocked integration + 1 live Nominatim precision test).
- **Live Nominatim GPS Precision Verification:**
  | Query | Resolved Coordinates | Reference Coordinates | Haversine Error |
  | :--- | :--- | :--- | :--- |
  | Baltit Fort, Hunza, Pakistan | `(36.325523, 74.669892)` | `(36.3256, 74.6678)` | **0.19 km** |
  | Faisal Mosque, Islamabad, Pakistan | `(33.729985, 73.037342)` | `(33.7295, 73.0372)` | **0.06 km** |
  | Eiffel Tower, Paris, France | `(48.85826, 2.294501)` | `(48.8584, 2.2945)` | **0.02 km** |
  - **Hit rate:** 3/3 (100%), **Mean GPS error:** 0.09 km.
- **Pytest & Coverage Output:** (`pytest --cov=app --cov-report=term-missing -v`)
  ```text
  tests/test_health.py (18 passed)
  tests/test_itinerary_api.py (16 passed, 1 live skipped)
  tests/test_geocoding.py (20 passed, 1 live passed with RUN_LIVE_TESTS=1)
  TOTAL: 538 statements, 18 missed, 97% coverage
  ======================== 54 passed, 2 skipped in 0.93s ========================
  ```
- **Notes / Observations:**
  - Unverified places safely keep `latitude: null`, `longitude: null`, `verified: false` (never fake `0.0, 0.0`), and geocoding HTTP failures never crash itinerary generation.
  - Ready for Caching, Rate Limiting & Slot Regeneration (M4).

---

## Milestone 4 (M4) Report
- **Date:** 2026-11-23
- **Features Completed:**
  - `app/services/cache_service.py`: Multi-backend async caching (`DiskCacheBackend` using a dedicated single-thread executor so SQLite never blocks FastAPI's event loop or leaks Windows file handles, `RedisCacheBackend` via `redis.asyncio` with graceful fallback on connection failure, and `MemoryCacheBackend` for isolated tests) with deterministic SHA-256 normalized cache keys (`build_itinerary_cache_key`).
  - `app/core/security.py`: SlowAPI rate-limiting middleware enforcing `5/day` on `POST /api/v1/itinerary/generate` and `20/day` on `POST /api/v1/itinerary/regenerate-slot` per user (`X-User-Id`) or client IP (`X-Forwarded-For` / remote IP), returning standardized `429 Too Many Requests` (`RATE_LIMIT_EXCEEDED`), plus constant-time `X-API-Key` header authentication (`verify_api_key`) when `API_KEY` is configured.
  - `POST /api/v1/itinerary/regenerate-slot`: Stateless single-activity replacement endpoint (`RegenerateSlotRequestSchema`) calling Gemini (`LLMActivity` structured output) and geocoding verification without regenerating the full trip.
  - `X-Cache: HIT | MISS` response header added to `POST /api/v1/itinerary/generate`.
  - `tests/test_cache_security_slot.py`: 10 tests covering cache normalization, DiskCache/Redis/Memory backends, `< 50ms` DiskCache latency benchmark, 5/day rate-limit enforcement (`429`), `X-API-Key` authentication (`401`), and `/regenerate-slot` with geocoding & error handling.
- **Installed versions added to `requirements.txt`:** `diskcache==5.6.3`, `redis==8.2.0`, `slowapi==0.1.10`
- **Performance & Rate-Limit Verification:**
  - **Real SQLite DiskCache hit latencies:** `[6.80 ms, 6.19 ms, 4.37 ms]` → **5.79 ms average** (target: `< 50 ms`).
  - **Rate limit enforcement:** Requests 1–5 from same IP returned `200 OK`; request 6 returned **`429 Too Many Requests`** (`RATE_LIMIT_EXCEEDED`); isolated separate user/IP returned `200 OK`.
- **Pytest & Coverage Output:** (`pytest --cov=app --cov-report=term-missing -q`)
  ```text
  tests/test_health.py (18 passed)
  tests/test_itinerary_api.py (16 passed, 1 live skipped)
  tests/test_geocoding.py (20 passed, 1 live skipped)
  tests/test_cache_security_slot.py (10 passed)
  TOTAL: 801 statements, 23 missed, 97% coverage
  64 passed, 2 skipped in 1.10s
  ```
- **Notes / Observations:**
  - Discovered and fixed a Windows-specific `diskcache` SQLite thread-local handle lock by isolating DiskCache I/O onto a dedicated single-thread executor (`DiskCacheBackend._ensure_cache`), ensuring clean shutdown and consistent ~5 ms cache hits.
  - Ready for Integration Testing, Docker & Production Readiness (M5).

---

## Milestone 5 (M5) Report — Final Release Audit (`v1.0.0`)
- **Date:** 2026-11-23
- **Features Completed:**
  - `backend/Dockerfile` & `backend/.dockerignore`: Multi-stage lightweight `python:3.11-slim` production container (stage 1 builds wheels; stage 2 installs offline wheels, creates non-root `appuser`, exposes port `8000`, includes `HEALTHCHECK` against `/api/v1/health`).
  - `.github/workflows/backend-ci.yml`: Automated GitHub Actions pipeline running on push/PR to `main` — `lint-and-test` (`black --check`, `flake8`, `pytest --cov=app --cov-fail-under=85`) followed by `docker-build` (`docker build -t ai-travel-planner-backend:ci ./backend`).
  - `backend/pyproject.toml` & `backend/.flake8`: Standardized 88-char formatting (`black==26.10.1`), linting (`flake8==7.5.0`), and coverage (`fail_under = 85`).
  - Finalized OpenAPI documentation (`app/main.py`): version `1.0.0`, full API description, structured `openapi_tags` (`Health`, `Itinerary`, `Weather`), verified Swagger UI (`/docs`), ReDoc (`/redoc`), and `/openapi.json` routes/tags in `tests/test_health.py`.
- **Quality Gate Results:**
  ```text
  black --check app tests   -> 29 files would be left unchanged (exit 0)
  flake8 app tests          -> 0 warnings / 0 errors (exit 0)
  pytest --cov=app --cov-fail-under=85 -> 64 passed, 2 skipped | 97.03% coverage (exit 0)
  ```
- **Notes / Observations:**
  - Local `docker build` was not executed because Docker Desktop's engine daemon (`dockerDesktopLinuxEngine`) was stopped on this machine; `docker-build` is configured to run automatically in GitHub Actions CI upon push and can be run locally once Docker Desktop is started.
  - All 5 milestones (M1–M5) are complete and tagged `v1.0.0`.

---

## Post-M5 Security Audit & Local Docker Verification (`v1.0.1`)
- **Date:** 2026-11-23
- **Vulnerabilities & Bugs Identified and Fixed (M1–M5 Audit):**
  1. **Rate-limit bypass via spoofable headers (`app/core/security.py`):** Removed untrusted `X-User-Id` override and gated `X-Forwarded-For` behind opt-in `TRUST_PROXY_HEADERS=true` with `ipaddress.ip_address` validation.
  2. **Unbounded trip duration & payload DoS (`app/models/request_schemas.py`):** Added strict caps (`MAX_TRIP_DURATION_DAYS = 14`, `MAX_INTERESTS_COUNT = 15`, `MAX_EXISTING_TITLES_COUNT = 50`, `MAX_BUDGET = 1_000_000`, `allow_inf_nan=False`) and control-character stripping.
  3. **Unprotected weather proxy (`app/api/v1/endpoints/weather.py`):** Added SlowAPI rate limiting (`60/hour`), `verify_api_key`, `follow_redirects=False`, and resilient parsing returning `502` on malformed upstream JSON.
  4. **CORS, security headers & unhandled exception handler (`app/main.py`, `app/core/exceptions.py`):** Configurable `CORS_ALLOW_ORIGINS`, restricted methods/headers, added `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store` on errors, and catch-all `500` handler preventing traceback leakage.
  5. **Bounded geocoding cache (`app/services/geocoding_service.py`):** Replaced unbounded `dict` with bounded `OrderedDict` LRU (`GEOCODING_CACHE_MAX_ENTRIES = 2000`) + `follow_redirects=False`.
  6. **Clean shutdown lifecycle (`app/main.py`):** Lifespan closes initialized cache backends on shutdown and logs a warning if `API_KEY` is unset in production.
  7. **Prompt-injection hardening (`app/utils/prompt_templates.py`):** Wrapped untrusted user parameters in `<user_request_data>` tags with explicit system-level non-override rules.
  8. **Production Docker image hygiene (`requirements.txt` vs `requirements-dev.txt`, `Dockerfile`):** Removed dev/test tools (`pytest`, `black`, `flake8`) from the production Docker image and removed the external `# syntax=` frontend pull.
  9. **Safe logging & `python -O` safety (`app/services/ai_engine.py`, `app/utils/distance_calculator.py`, `app/core/config.py`):** Sanitized Gemini error logs, replaced `assert` statements in runtime paths, and enforced `https://` for upstream URLs.
- **Verified Local Docker Build & Live Container Smoke Test:**
  ```text
  Image:          ai-travel-planner-backend:1.0.0 (356MB)
  Container User: uid=1000(appuser) gid=1000(appgroup) (non-root)
  GET /api/v1/health -> 200 OK {"status":"ok","environment":"production",...}
  Security Headers   -> X-Content-Type-Options: nosniff, X-Frame-Options: DENY
  GET /docs          -> 200 OK
  Dev tools in prod  -> PYTEST_IN_PROD=False
  ```
- **Final Hardened Quality Gate:**
  ```text
  black --check app tests -> 29 files would be left unchanged (exit 0)
  flake8 app tests        -> 0 errors (exit 0)
  pytest --cov=app --cov-fail-under=85 -> 67 passed, 2 skipped | 95.34% coverage (exit 0)
  ```

---
