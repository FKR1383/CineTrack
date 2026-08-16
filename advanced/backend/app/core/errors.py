from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError

logger = logging.getLogger(__name__)


class AppError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        detail: str | None = None,
        fields: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.detail = detail
        self.fields = fields


def error_payload(
    request: Request,
    *,
    status_code: int,
    code: str,
    message: str,
    detail: str | None = None,
    fields: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request_id = getattr(request.state, "request_id", None)
    return {
        "error": {
            "status_code": status_code,
            "code": code,
            "message": message,
            "detail": detail,
            "fields": fields,
            "request_id": request_id,
        }
    }


def install_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=error_payload(
                request,
                status_code=exc.status_code,
                code=exc.code,
                message=exc.message,
                detail=exc.detail,
                fields=exc.fields,
            ),
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        field_errors: dict[str, list[str]] = {}
        for item in exc.errors():
            path = ".".join(str(part) for part in item.get("loc", []) if part != "body") or "request"
            field_errors.setdefault(path, []).append(item.get("msg", "Invalid value"))
        return JSONResponse(
            status_code=422,
            content=error_payload(
                request,
                status_code=422,
                code="validation_error",
                message="اطلاعات ورودی معتبر نیست.",
                detail="One or more request fields failed server-side validation.",
                fields=field_errors,
            ),
        )

    @app.exception_handler(IntegrityError)
    async def handle_integrity_error(request: Request, exc: IntegrityError) -> JSONResponse:
        logger.warning("Database integrity error", exc_info=exc)
        return JSONResponse(
            status_code=409,
            content=error_payload(
                request,
                status_code=409,
                code="conflict",
                message="این عملیات با اطلاعات موجود تداخل دارد.",
                detail="A unique or relational database constraint was violated.",
            ),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled server error", exc_info=exc)
        return JSONResponse(
            status_code=500,
            content=error_payload(
                request,
                status_code=500,
                code="internal_server_error",
                message="خطای غیرمنتظره‌ای در سرور رخ داد.",
                detail="Please retry later and provide the request_id to support.",
            ),
        )
