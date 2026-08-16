from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.config import get_settings
from app.core.errors import AppError

settings = get_settings()
password_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return password_hasher.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    try:
        return password_hasher.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def _encode(payload: dict[str, Any], expires_delta: timedelta) -> str:
    now = datetime.now(timezone.utc)
    claims = {
        **payload,
        "iat": now,
        "nbf": now,
        "exp": now + expires_delta,
        "iss": "timetv-advanced",
        "aud": "timetv-mobile",
    }
    return jwt.encode(
        claims,
        settings.jwt_secret.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )


def create_access_token(user_id: str, role: str) -> tuple[str, datetime]:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_minutes)
    token = _encode(
        {"sub": user_id, "role": role, "type": "access", "jti": str(uuid.uuid4())},
        timedelta(minutes=settings.access_token_minutes),
    )
    return token, expires


def create_refresh_token(
    user_id: str, role: str, *, remember_me: bool
) -> tuple[str, str, datetime]:
    days = settings.refresh_token_days  # Course requirement: valid session for 30 days after login.
    jti = str(uuid.uuid4())
    expires = datetime.now(timezone.utc) + timedelta(days=days)
    token = _encode(
        {"sub": user_id, "role": role, "type": "refresh", "jti": jti},
        timedelta(days=days),
    )
    return token, jti, expires


def decode_token(token: str, expected_type: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret.get_secret_value(),
            algorithms=[settings.jwt_algorithm],
            audience="timetv-mobile",
            issuer="timetv-advanced",
        )
    except jwt.ExpiredSignatureError as exc:
        raise AppError(401, "token_expired", "نشست شما منقضی شده است.") from exc
    except jwt.PyJWTError as exc:
        raise AppError(401, "invalid_token", "توکن احراز هویت معتبر نیست.") from exc
    if payload.get("type") != expected_type:
        raise AppError(401, "invalid_token_type", "نوع توکن معتبر نیست.")
    if not payload.get("sub") or not payload.get("jti"):
        raise AppError(401, "invalid_token", "توکن احراز هویت ناقص است.")
    return payload


def create_reset_token() -> tuple[str, str]:
    raw = secrets.token_urlsafe(48)
    return raw, hash_reset_token(raw)


def hash_reset_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
