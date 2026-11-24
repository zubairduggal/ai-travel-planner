"""Open-Meteo weather forecast service and WMO code interpretation."""

from datetime import date

import httpx

from app.core.config import Settings
from app.core.exceptions import ExternalServiceError, ExternalServiceTimeoutError
from app.models.response_schemas import DailyWeatherSchema, WeatherResponseSchema

# Standard WMO weather interpretation codes returned by Open-Meteo.
WMO_WEATHER_CODES: dict[int, str] = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    71: "Slight snow",
    73: "Moderate snow",
    75: "Heavy snow",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    95: "Thunderstorm",
}


def describe_weather_code(code: int | None) -> str:
    if code is None:
        return "Unknown"
    return WMO_WEATHER_CODES.get(code, f"Weather code {code}")


async def fetch_weather_forecast(
    *,
    lat: float,
    lon: float,
    days: int,
    settings: Settings,
    http_client: httpx.AsyncClient | None = None,
) -> WeatherResponseSchema:
    """Fetch and parse a daily weather forecast from Open-Meteo."""
    params = {
        "latitude": lat,
        "longitude": lon,
        "forecast_days": days,
        "daily": (
            "temperature_2m_max,temperature_2m_min,"
            "precipitation_probability_max,weather_code"
        ),
        "timezone": "auto",
    }

    try:
        if http_client is not None:
            response = await http_client.get(
                settings.weather_base_url,
                params=params,
                timeout=settings.weather_timeout_seconds,
                follow_redirects=False,
            )
        else:
            async with httpx.AsyncClient(
                timeout=settings.weather_timeout_seconds,
                follow_redirects=False,
            ) as client:
                response = await client.get(settings.weather_base_url, params=params)
        response.raise_for_status()
        payload = response.json()
    except httpx.TimeoutException as exc:
        raise ExternalServiceTimeoutError("Weather service timed out.") from exc
    except (httpx.HTTPError, ValueError) as exc:
        raise ExternalServiceError("Failed to fetch weather forecast.") from exc

    try:
        if not isinstance(payload, dict):
            raise ValueError("Unexpected weather payload type")
        daily_raw = payload.get("daily", {})
        if not isinstance(daily_raw, dict):
            raise ValueError("Unexpected daily forecast payload")
        dates = daily_raw.get("time", [])
        max_temps = daily_raw.get("temperature_2m_max", [])
        min_temps = daily_raw.get("temperature_2m_min", [])
        precip_probs = daily_raw.get("precipitation_probability_max", [])
        codes = daily_raw.get("weather_code", [])

        daily: list[DailyWeatherSchema] = []
        for idx, day_str in enumerate(dates):
            code = codes[idx] if idx < len(codes) else None
            daily.append(
                DailyWeatherSchema(
                    date=date.fromisoformat(day_str),
                    temp_max_c=max_temps[idx] if idx < len(max_temps) else None,
                    temp_min_c=min_temps[idx] if idx < len(min_temps) else None,
                    precipitation_probability_max=(
                        precip_probs[idx] if idx < len(precip_probs) else None
                    ),
                    weather_code=code,
                    condition=describe_weather_code(code),
                )
            )

        return WeatherResponseSchema(
            latitude=float(payload.get("latitude", lat)),
            longitude=float(payload.get("longitude", lon)),
            timezone=str(payload.get("timezone", "UTC")),
            daily=daily,
        )
    except (KeyError, TypeError, ValueError, AttributeError) as exc:
        raise ExternalServiceError("Invalid weather data from provider.") from exc
