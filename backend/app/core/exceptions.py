"""Custom API exceptions and JSON error handlers.

Every error leaves the API in the same envelope so the Flutter client can
handle it in one place:

    {"error": {"code": "AI_TIMEOUT", "message": "..."}}
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)


class AppError(Exception):
    """Base class for errors that map to a specific HTTP response."""

    status_code: int = 500
    code: str = "INTERNAL_ERROR"
    message: str = "An unexpected error occurred."

    def __init__(self, message: str | None = None) -> None:
        self.message = message or self.message
        super().__init__(self.message)


class AINotConfiguredError(AppError):
    """No OpenRouter API key is configured on the server."""

    status_code = 503
    code = "AI_NOT_CONFIGURED"
    message = "The AI service is not configured on the server."


class AIAuthError(AppError):
    """OpenRouter rejected the configured API key."""

    status_code = 503
    code = "AI_AUTH_FAILED"
    message = "The AI service rejected the server's API key."


class AIRateLimitError(AppError):
    """OpenRouter quota / rate limit was exceeded (HTTP 402/429)."""

    status_code = 503
    code = "AI_RATE_LIMITED"
    message = "The AI service is temporarily over its quota. Try again later."


class AITimeoutError(AppError):
    """OpenRouter did not answer within the configured timeout."""

    status_code = 504
    code = "AI_TIMEOUT"
    message = "The AI service took too long to respond."


class AIProviderError(AppError):
    """Any other error returned by the OpenRouter API."""

    status_code = 502
    code = "AI_PROVIDER_ERROR"
    message = "The AI service returned an error."


class AIResponseError(AppError):
    """OpenRouter answered, but the output was not a valid itinerary."""

    status_code = 502
    code = "AI_INVALID_RESPONSE"
    message = "The AI service returned an invalid itinerary."


class ExternalServiceError(AppError):
    """An upstream external API (e.g. weather proxy) failed."""

    status_code = 502
    code = "EXTERNAL_SERVICE_ERROR"
    message = "An upstream external service returned an error."


class ExternalServiceTimeoutError(AppError):
    """An upstream external API timed out."""

    status_code = 504
    code = "EXTERNAL_SERVICE_TIMEOUT"
    message = "An upstream external service timed out."


class UnauthorizedError(AppError):
    """Missing or invalid client API key."""

    status_code = 401
    code = "UNAUTHORIZED"
    message = "Invalid or missing API key."


async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": exc.message}},
        headers={"Cache-Control": "no-store"},
    )


async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    """Catch-all handler so internal tracebacks are never leaked to clients."""
    logger.exception("Unhandled server error: %s", type(exc).__name__)
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An unexpected error occurred.",
            }
        },
        headers={"Cache-Control": "no-store"},
    )


async def validation_exception_handler(
    _: Request, exc: RequestValidationError
) -> JSONResponse:
    """Return a clean 422 envelope without failing on NaN/Infinity inputs."""
    errors = exc.errors()
    first_msg = (
        str(errors[0].get("msg"))
        if errors and isinstance(errors[0], dict) and errors[0].get("msg")
        else "Invalid request parameters."
    )
    return JSONResponse(
        status_code=422,
        content={"error": {"code": "VALIDATION_ERROR", "message": first_msg}},
        headers={"Cache-Control": "no-store"},
    )


async def http_exception_handler(
    _: Request, exc: StarletteHTTPException
) -> JSONResponse:
    """Standardize 404/405/HTTP exceptions into the uniform error envelope."""
    code_map = {
        404: "NOT_FOUND",
        405: "METHOD_NOT_ALLOWED",
    }
    code = code_map.get(exc.status_code, f"HTTP_{exc.status_code}")
    message = exc.detail if isinstance(exc.detail, str) else "Request failed."
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": code, "message": message}},
        headers={"Cache-Control": "no-store"},
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)
