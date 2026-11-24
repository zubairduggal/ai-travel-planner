# AI-Powered Travel Planner

Full-stack travel itinerary planning project containing a Python FastAPI backend (`backend/`) and a Flutter mobile/web frontend (`frontend/`).

## Repository Structure

- `backend/` — FastAPI REST API (`GET /api/v1/health`, `POST /api/v1/itinerary/generate`, `POST /api/v1/itinerary/regenerate-slot`, `GET /api/v1/weather`), Gemini AI engine, OpenStreetMap Nominatim geocoding, Haversine feasibility checks, caching (`disk`/`redis`/`memory`), SlowAPI rate limiting, and multi-stage `Dockerfile`. See [backend/README.md](backend/README.md) and [backend/reports.md](backend/reports.md).
- `frontend/` — Flutter Material 3 application (`material_ui`, `provider`, `dio`, `flutter_map`, `hive_ce`, `pdf`, `printing`, `share_plus`, `firebase_core`, `firebase_auth`, `google_sign_in`, `sign_in_with_apple`, `firebase_crashlytics`). See [frontend_reports.md](frontend_reports.md).
- `.github/workflows/backend-ci.yml` — Backend CI (`black --check`, `flake8`, `pytest --cov=app --cov-fail-under=85`, `docker build`).
- `.github/workflows/frontend-ci.yml` — Frontend CI (`flutter analyze`, `flutter test -r expanded`, `flutter build apk --debug`).

## Running the Backend

Requirements: Python 3.11+ (or Docker) and a Google Gemini API key for live itinerary generation.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
# Edit .env and set GEMINI_API_KEY
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Endpoints when running locally:
- Health check: `http://127.0.0.1:8000/api/v1/health`
- Swagger UI: `http://127.0.0.1:8000/docs`
- ReDoc: `http://127.0.0.1:8000/redoc`

### Backend Quality Checks

```powershell
cd backend
.\.venv\Scripts\python.exe -m black --check app tests
.\.venv\Scripts\python.exe -m flake8 app tests
.\.venv\Scripts\python.exe -m pytest --cov=app --cov-report=term-missing --cov-fail-under=85 -v
```

### Backend Docker Build & Run

```powershell
docker build -t ai-travel-planner-backend ./backend
docker run --rm -p 8000:8000 --env-file ./backend/.env ai-travel-planner-backend
```

## Running the Frontend

Requirements: Flutter SDK (verified with Flutter 3.50.1 / Dart 3.14.0).

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test -r expanded
```

Optional overrides at runtime via `--dart-define`:
- `API_BASE_URL` (defaults to `http://10.0.2.2:8000` on Android, `http://127.0.0.1:8000` on Web/iOS/Desktop)
- `API_KEY` (optional `X-API-Key` header value)
- `RUN_LIVE_E2E=true` (enables `frontend/test/live_backend_e2e_test.dart` against a running local backend)
