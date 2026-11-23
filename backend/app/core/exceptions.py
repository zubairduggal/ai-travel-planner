"""Custom API exceptions and JSON error handlers.

Every error leaves the API in the same envelope so the Flutter client can
handle it in one place:

    {"error": {"code": "AI_TIMEOUT", "message": "..."}}
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    """Base class for errors that map to a specific HTTP response."""

    status_code: int = 500
    code: str = "INTERNAL_ERROR"
    message: str = "An unexpected error occurred."

    def __init__(self, message: str | None = None) -> None:
        self.message = message or self.message
        super().__init__(self.message)


class AINotConfiguredError(AppError):
    """No Gemini API key is configured on the server."""

    status_code = 503
    code = "AI_NOT_CONFIGURED"
    message = "The AI service is not configured on the server."


class AIAuthError(AppError):
    """Gemini rejected the configured API key."""

    status_code = 503
    code = "AI_AUTH_FAILED"
    message = "The AI service rejected the server's API key."


class AIRateLimitError(AppError):
    """Gemini quota / rate limit was exceeded (HTTP 429 from Gemini)."""

    status_code = 503
    code = "AI_RATE_LIMITED"
    message = "The AI service is temporarily over its quota. Try again later."


class AITimeoutError(AppError):
    """Gemini did not answer within the configured timeout."""

    status_code = 504
    code = "AI_TIMEOUT"
    message = "The AI service took too long to respond."


class AIProviderError(AppError):
    """Any other error returned by the Gemini API."""

    status_code = 502
    code = "AI_PROVIDER_ERROR"
    message = "The AI service returned an error."


class AIResponseError(AppError):
    """Gemini answered, but the output was not a valid itinerary."""

    status_code = 502
    code = "AI_INVALID_RESPONSE"
    message = "The AI service returned an invalid itinerary."


async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
