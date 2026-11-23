# AI-Powered Travel Planner — Backend

FastAPI backend for the AI-Powered Travel Planner Flutter app.

**Current status:** Milestone 3 (Geocoding, Location Verification & Weather) complete. See [reports.md](reports.md).

## Requirements
- Python 3.11+
- A Google Gemini API key (for live itinerary generation)

## Setup (Windows PowerShell)
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
# Edit .env and set GEMINI_API_KEY=<your_key>
```

## Run the server
```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```
- Health check: http://127.0.0.1:8000/api/v1/health
- Weather forecast: http://127.0.0.1:8000/api/v1/weather?lat=36.3256&lon=74.6678&days=5
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

## Run tests
```powershell
# Unit & mocked integration tests with coverage
.\.venv\Scripts\python.exe -m pytest --cov=app -v

# Run live Nominatim GPS precision test
$env:RUN_LIVE_TESTS="1"; .\.venv\Scripts\python.exe -m pytest tests/test_geocoding.py -m live -v

# Run live Gemini integration test (requires GEMINI_API_KEY)
$env:RUN_LIVE_TESTS="1"; $env:GEMINI_API_KEY="your_key"; .\.venv\Scripts\python.exe -m pytest tests/test_itinerary_api.py -m live -v
```

## Configuration (`.env`)
| Variable | Default | Description |
| :--- | :--- | :--- |
| `APP_NAME` | `AI Travel Planner API` | Title shown in API docs |
| `APP_VERSION` | `0.3.0` | API version |
| `APP_ENV` | `development` | `development`, `staging`, or `production` |
| `DEBUG` | `false` | FastAPI debug mode |
| `API_V1_PREFIX` | `/api/v1` | Prefix for v1 routes |
| `GEMINI_API_KEY` | *(unset)* | Google Gemini API key (required for `/generate`) |
| `GEMINI_MODEL` | `gemini-3.8-flash` | Gemini model ID |
| `GEMINI_TIMEOUT_SECONDS` | `60` | Timeout per Gemini call (seconds) |
| `GEMINI_TEMPERATURE` | `0.4` | Sampling temperature (`0`–`2`) |
| `GEMINI_MAX_RETRIES` | `1` | Retries when Gemini returns malformed JSON |
| `NOMINATIM_USER_AGENT` | `AITravelPlanner/0.3.0 (...)` | Required custom User-Agent for OpenStreetMap Nominatim |
| `NOMINATIM_MIN_INTERVAL_SECONDS` | `1.05` | Enforces Nominatim <= 1 req/sec policy |
| `GOOGLE_PLACES_API_KEY` | *(unset)* | Optional Google Places API (New) fallback |
| `MAX_SAME_DAY_DISTANCE_KM` | `50.0` | Haversine threshold for same-day feasibility warnings |
| `WEATHER_BASE_URL` | `https://api.open-meteo.com/v1/forecast` | Open-Meteo forecast endpoint (no API key needed) |

## API Endpoints
| Method | Path | Milestone | Status |
| :--- | :--- | :--- | :--- |
| GET | `/api/v1/health` | M1 | Done |
| POST | `/api/v1/itinerary/generate` | M2 + M3 | Done |
| GET | `/api/v1/weather` | M3 | Done |
| POST | `/api/v1/itinerary/regenerate-slot` | M4 | Planned |
