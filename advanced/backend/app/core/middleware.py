from __future__ import annotations

import json
import time
import uuid
from collections import defaultdict, deque
from collections.abc import Awaitable, Callable
from threading import Lock
from typing import Any

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from app.config import get_settings

settings = get_settings()


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))[:100]
        request.state.request_id = request_id
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Process-Time-Ms"] = f"{(time.perf_counter() - started) * 1000:.2f}"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        if settings.is_production:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Small dependency-free limiter; Nginx also enforces a production edge limit."""

    def __init__(self, app: Any) -> None:
        super().__init__(app)
        self._requests: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        if request.url.path in {"/health", "/ready", "/docs", "/openapi.json"}:
            return await call_next(request)
        forwarded = request.headers.get("X-Forwarded-For", "")
        client_ip = forwarded.split(",")[0].strip() if forwarded else None
        identity = client_ip or (request.client.host if request.client else "unknown")
        now = time.monotonic()
        with self._lock:
            bucket = self._requests[identity]
            while bucket and bucket[0] < now - 60:
                bucket.popleft()
            if len(bucket) >= settings.rate_limit_per_minute:
                payload = {
                    "error": {
                        "status_code": 429,
                        "code": "rate_limit_exceeded",
                        "message": "تعداد درخواست‌ها بیش از حد مجاز است.",
                        "detail": "Retry after one minute.",
                        "fields": None,
                        "request_id": getattr(request.state, "request_id", None),
                    }
                }
                return JSONResponse(payload, status_code=429, headers={"Retry-After": "60"})
            bucket.append(now)
        return await call_next(request)
