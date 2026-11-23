# AI-Powered Travel Planner — Backend

FastAPI backend for the AI-Powered Travel Planner Flutter app.

**Current status:** Milestone 2 (AI Itinerary Engine — Gemini Integration) complete. See [reports.md](reports.md).

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
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

## Run tests
```powershell
# Unit & mocked integration tests with coverage
.\.venv\Scripts\python.exe -m pytest --cov=app -v

# Include live Gemini integration test (requires GEMINI_API_KEY in env/.env)
$env:RUN_LIVE_TESTS="1"; $env:GEMINI_API_KEY="your_key"; .\.venv\Scripts\python.exe -m pytest -m live -v
```

## Configuration (`.env`)
| Variable | Default | Description |
| :--- | :--- | :--- |
| `APP_NAME` | `AI Travel Planner API` | Title shown in API docs |
| `APP_VERSION` | `0.2.0` | API version |
| `APP_ENV` | `development` | `development`, `staging`, or `production` |
| `DEBUG` | `false` | FastAPI debug mode |
| `API_V1_PREFIX` | `/api/v1` | Prefix for v1 routes |
| `GEMINI_API_KEY` | *(unset)* | Google Gemini API key (required for `/generate`) |
| `GEMINI_MODEL` | `gemini-3.8-flash` | Gemini model ID |
| `GEMINI_TIMEOUT_SECONDS` | `60` | Timeout per Gemini call (seconds) |
| `GEMINI_TEMPERATURE` | `0.4` | Sampling temperature (`0`–`2`) |
| `GEMINI_MAX_RETRIES` | `1` | Retries when Gemini returns malformed JSON |

## API Endpoints
| Method | Path | Milestone | Status |
| :--- | :--- | :--- | :--- |
| GET | `/api/v1/health` | M1 | Done |
| POST | `/api/v1/itinerary/generate` | M2 | Done |
| POST | `/api/v1/itinerary/regenerate-slot` | M4 | Planned |
