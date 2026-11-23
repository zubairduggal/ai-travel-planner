# AI-Powered Travel Planner — Backend

FastAPI backend for the AI-Powered Travel Planner Flutter app.

**Current status:** Milestone 1 (Core API setup) complete. See [reports.md](reports.md).

## Requirements
- Python 3.11+

## Setup (Windows PowerShell)
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
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
.\.venv\Scripts\python.exe -m pytest -v
```

## Configuration (`.env`)
| Variable | Default | Description |
| :--- | :--- | :--- |
| `APP_NAME` | `AI Travel Planner API` | Title shown in API docs |
| `APP_VERSION` | `0.1.0` | API version |
| `APP_ENV` | `development` | `development`, `staging`, or `production` |
| `DEBUG` | `false` | FastAPI debug mode |
| `API_V1_PREFIX` | `/api/v1` | Prefix for v1 routes |

## API Endpoints
| Method | Path | Milestone | Status |
| :--- | :--- | :--- | :--- |
| GET | `/api/v1/health` | M1 | Done |
| POST | `/api/v1/itinerary/generate` | M2 | Planned |
| POST | `/api/v1/itinerary/regenerate-slot` | M4 | Planned |
