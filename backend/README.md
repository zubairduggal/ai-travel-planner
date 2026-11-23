# AI-Powered Travel Planner — Backend (`v1.0.0`)

Production-ready FastAPI backend for the AI-Powered Travel Planner Flutter app.

**Status:** All milestones **M1–M5 complete** (`v1.0.0`, **97.03% test coverage**, `black` & `flake8` clean). See [reports.md](reports.md) for full milestone logs.

## Requirements
- Python 3.11+ (or Docker)
- A Google Gemini API key (for live itinerary generation)
- Optional: Redis server for production distributed caching & rate limiting

## Local Setup (Windows PowerShell)
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
# Edit .env and set GEMINI_API_KEY=<your_key>
```

## Run Locally
```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```
- Health check: http://127.0.0.1:8000/api/v1/health
- Weather forecast: http://127.0.0.1:8000/api/v1/weather?lat=36.3256&lon=74.6678&days=5
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

## Run with Docker
```powershell
# Build multi-stage production image
docker build -t ai-travel-planner-backend ./backend

# Run container (passing .env for GEMINI_API_KEY, API_KEY, etc.)
docker run --rm -p 8000:8000 --env-file ./backend/.env ai-travel-planner-backend
```

## Tests, Coverage & Linting
```powershell
cd backend
.\.venv\Scripts\python.exe -m black --check app tests
.\.venv\Scripts\python.exe -m flake8 app tests
.\.venv\Scripts\python.exe -m pytest --cov=app --cov-report=term-missing --cov-fail-under=85 -v

# Optional live API tests:
$env:RUN_LIVE_TESTS="1"; .\.venv\Scripts\python.exe -m pytest tests/test_geocoding.py -m live -v
$env:RUN_LIVE_TESTS="1"; $env:GEMINI_API_KEY="your_key"; .\.venv\Scripts\python.exe -m pytest tests/test_itinerary_api.py -m live -v
```

## CI/CD
GitHub Actions ([.github/workflows/backend-ci.yml](../.github/workflows/backend-ci.yml)) automatically runs on every push and PR to `main`:
1. `black --check app tests`
2. `flake8 app tests`
3. `pytest --cov=app --cov-fail-under=85`
4. `docker build -t ai-travel-planner-backend:ci ./backend`

## Configuration (`.env`)
| Variable | Default | Description |
| :--- | :--- | :--- |
| `APP_NAME` | `AI Travel Planner API` | Title shown in API docs |
| `APP_VERSION` | `1.0.0` | API version |
| `APP_ENV` | `development` | `development`, `staging`, or `production` |
| `DEBUG` | `false` | FastAPI debug mode |
| `API_V1_PREFIX` | `/api/v1` | Prefix for v1 routes |
| `GEMINI_API_KEY` | *(unset)* | Google Gemini API key (required for `/generate` & `/regenerate-slot`) |
| `GEMINI_MODEL` | `gemini-3.5-flash-lite` | Primary Gemini model ID |
| `GEMINI_FALLBACK_MODEL` | `gemini-3.8-flash` | Automatic fallback model on 503 high demand |
| `GEMINI_TIMEOUT_SECONDS` | `60` | Timeout per Gemini call (seconds) |
| `GEMINI_TEMPERATURE` | `0.4` | Sampling temperature (`0`–`2`) |
| `GEMINI_MAX_RETRIES` | `1` | Retries when Gemini returns malformed JSON |
| `NOMINATIM_USER_AGENT` | `AITravelPlanner/1.0.0 (...)` | Required custom User-Agent for OpenStreetMap Nominatim |
| `NOMINATIM_MIN_INTERVAL_SECONDS` | `1.05` | Enforces Nominatim <= 1 req/sec policy |
| `GOOGLE_PLACES_API_KEY` | *(unset)* | Optional Google Places API (New) fallback |
| `MAX_SAME_DAY_DISTANCE_KM` | `50.0` | Haversine threshold for same-day feasibility warnings |
| `WEATHER_BASE_URL` | `https://api.open-meteo.com/v1/forecast` | Open-Meteo forecast endpoint (no API key needed) |
| `CACHE_BACKEND` | `disk` | `disk` (local SQLite DiskCache), `redis`, or `memory` |
| `DISKCACHE_DIR` | `.cache/itineraries` | Directory for local DiskCache storage |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis URL when `CACHE_BACKEND=redis` |
| `CACHE_TTL_SECONDS` | `86400` | Cache expiry in seconds (default 24h) |
| `RATE_LIMIT_ITINERARY` | `5/day` | Max `/generate` calls per IP/User per day |
| `RATE_LIMIT_REGENERATE_SLOT` | `20/day` | Max `/regenerate-slot` calls per IP/User per day |
| `RATE_LIMIT_STORAGE_URI` | `memory://` | `memory://` for dev or `redis://...` for prod |
| `API_KEY` | *(unset)* | Optional `X-API-Key` secret for itinerary routes |

## API Endpoints
| Method | Path | Auth / Limit | Status |
| :--- | :--- | :--- | :--- |
| GET | `/api/v1/health` | Public | Done |
| POST | `/api/v1/itinerary/generate` | Optional `X-API-Key`, `5/day`, cached | Done |
| POST | `/api/v1/itinerary/regenerate-slot` | Optional `X-API-Key`, `20/day` | Done |
| GET | `/api/v1/weather` | Public | Done |
