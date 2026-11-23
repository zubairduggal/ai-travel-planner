# Backend Development & Testing Reports

## Milestone Execution Summary

| Milestone | Status | Test Coverage | GitHub Commit Hash | Date Completed |
| :--- | :--- | :--- | :--- | :--- |
| **M1: Core API Setup** | Completed | Not measured (`pytest-cov` is added in M5); 18/18 tests passed | `3b142a8` | 2026-11-23 |
| **M2: AI Itinerary Engine** | Completed | 99% (34 passed, 1 live skipped) | _pending commit_ | 2026-11-23 |
| **M3: Geocoding & Verification**| Pending | - | - | - |
| **M4: Caching & Rate Limit** | Pending | - | - | - |
| **M5: Docker & Production** | Pending | - | - | - |

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
