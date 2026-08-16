from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.security import decode_token
from app.database import get_db
from app.models import User

bearer_scheme = HTTPBearer(auto_error=False)
DB = Annotated[Session, Depends(get_db)]


def get_current_user(
    db: DB,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppError(401, "authentication_required", "برای انجام این عملیات وارد حساب شوید.")
    payload = decode_token(credentials.credentials, "access")
    user = db.get(User, payload["sub"])
    if user is None or not user.is_active:
        raise AppError(401, "inactive_or_missing_user", "حساب کاربری فعال نیست.")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def get_optional_user(
    db: DB,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User | None:
    if credentials is None or credentials.scheme.lower() != "bearer":
        return None
    try:
        payload = decode_token(credentials.credentials, "access")
    except AppError:
        return None
    user = db.get(User, payload["sub"])
    return user if user and user.is_active else None


OptionalUser = Annotated[User | None, Depends(get_optional_user)]


def require_admin(current_user: CurrentUser) -> User:
    if current_user.role != "admin":
        raise AppError(403, "admin_required", "دسترسی مدیر سیستم لازم است.")
    return current_user


AdminUser = Annotated[User, Depends(require_admin)]
