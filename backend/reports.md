# Backend Development & Testing Reports

## Milestone Execution Summary

| Milestone | Status | Test Coverage | GitHub Commit Hash | Date Completed |
| :--- | :--- | :--- | :--- | :--- |
| **M1: Core API Setup** | Completed (not yet pushed) | Not measured (`pytest-cov` is added in M5) | - (Git not installed) | 2026-11-23 |
| **M2: AI Itinerary Engine** | Pending | - | - | - |
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
  - The commit/push step is blocked: `git` is not installed / not on PATH on this machine.
  - Ready for Gemini API integration (M2).

---
