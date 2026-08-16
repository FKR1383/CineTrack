from __future__ import annotations

import json
import threading
import time
from typing import Any, Protocol

from app.config import get_settings


class Cache(Protocol):
    def get_json(self, key: str) -> Any | None: ...
    def set_json(self, key: str, value: Any, ttl_seconds: int) -> None: ...
    def delete(self, key: str) -> None: ...


class MemoryCache:
    def __init__(self) -> None:
        self._values: dict[str, tuple[float, str]] = {}
        self._lock = threading.Lock()

    def get_json(self, key: str) -> Any | None:
        with self._lock:
            item = self._values.get(key)
            if not item:
                return None
            expires, raw = item
            if expires < time.monotonic():
                self._values.pop(key, None)
                return None
            return json.loads(raw)

    def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        with self._lock:
            self._values[key] = (time.monotonic() + ttl_seconds, json.dumps(value))

    def delete(self, key: str) -> None:
        with self._lock:
            self._values.pop(key, None)


class RedisCache:
    def __init__(self, url: str) -> None:
        import redis

        self._client = redis.Redis.from_url(url, decode_responses=True)
        self._client.ping()

    def get_json(self, key: str) -> Any | None:
        raw = self._client.get(key)
        return json.loads(raw) if raw else None

    def set_json(self, key: str, value: Any, ttl_seconds: int) -> None:
        self._client.setex(key, ttl_seconds, json.dumps(value))

    def delete(self, key: str) -> None:
        self._client.delete(key)


_cache: Cache | None = None


def get_cache() -> Cache:
    global _cache
    if _cache is not None:
        return _cache
    settings = get_settings()
    if settings.redis_url:
        try:
            _cache = RedisCache(settings.redis_url)
            return _cache
        except Exception:
            # Availability is more important than cache; database cache remains active.
            pass
    _cache = MemoryCache()
    return _cache
