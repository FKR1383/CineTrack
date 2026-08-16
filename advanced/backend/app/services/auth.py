from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.core.errors import AppError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    create_reset_token,
    decode_token,
    hash_password,
    hash_reset_token,
    password_needs_rehash,
    verify_password,
)
from app.models import PasswordResetToken, RefreshToken, User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserResponse
from app.services.mail import send_password_reset

settings = get_settings()


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def normalize_email(email: str) -> str:
    return email.strip().casefold()


def normalize_username(username: str) -> str:
    return username.strip()


def register_user(db: Session, data: RegisterRequest, avatar_url: str | None = None) -> User:
    email = normalize_email(str(data.email))
    username = normalize_username(data.username)
    existing = db.scalar(
        select(User).where(or_(func.lower(User.email) == email, func.lower(User.username) == username.casefold()))
    )
    if existing:
        field = "email" if existing.email.casefold() == email else "username"
        raise AppError(
            409,
            f"duplicate_{field}",
            "ایمیل یا نام کاربری قبلاً ثبت شده است.",
            fields={field: ["Already registered"]},
        )
    user = User(
        first_name=data.first_name.strip(),
        last_name=data.last_name.strip(),
        username=username,
        email=email,
        password_hash=hash_password(data.password),
        avatar_url=avatar_url,
        bio=data.bio.strip() if data.bio else None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def authenticate(db: Session, email: str, password: str) -> User:
    user = db.scalar(select(User).where(func.lower(User.email) == normalize_email(email)))
    if user is None or not verify_password(password, user.password_hash):
        raise AppError(401, "invalid_credentials", "ایمیل یا رمز عبور نادرست است.")
    if not user.is_active:
        raise AppError(403, "account_disabled", "حساب کاربری غیرفعال شده است.")
    if password_needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)
        db.commit()
    return user


def issue_tokens(
    db: Session, user: User, *, remember_me: bool, device_info: str | None = None
) -> TokenResponse:
    access_token, access_expires = create_access_token(user.id, user.role)
    refresh_token, jti, refresh_expires = create_refresh_token(
        user.id, user.role, remember_me=remember_me
    )
    db.add(
        RefreshToken(
            user_id=user.id,
            jti=jti,
            expires_at=refresh_expires,
            device_info=device_info,
        )
    )
    db.commit()
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        access_token_expires_at=access_expires,
        refresh_token_expires_at=refresh_expires,
        user=UserResponse.model_validate(user),
    )


def login(db: Session, data: LoginRequest) -> TokenResponse:
    user = authenticate(db, str(data.email), data.password)
    return issue_tokens(
        db, user, remember_me=data.remember_me, device_info=data.device_info
    )


def rotate_refresh_token(
    db: Session, raw_token: str, *, device_info: str | None = None
) -> TokenResponse:
    payload = decode_token(raw_token, "refresh")
    record = db.scalar(select(RefreshToken).where(RefreshToken.jti == payload["jti"]))
    now = datetime.now(timezone.utc)
    if record is None or record.revoked_at is not None or _as_utc(record.expires_at) <= now:
        raise AppError(401, "refresh_token_revoked", "نشست معتبر نیست؛ دوباره وارد شوید.")
    user = db.get(User, payload["sub"])
    if user is None or not user.is_active:
        raise AppError(401, "inactive_or_missing_user", "حساب کاربری فعال نیست.")
    record.revoked_at = now
    db.commit()
    remembered = (_as_utc(record.expires_at) - _as_utc(record.created_at)) > timedelta(days=2)
    return issue_tokens(
        db,
        user,
        remember_me=remembered,
        device_info=device_info or record.device_info,
    )


def logout(db: Session, raw_token: str) -> None:
    try:
        payload = decode_token(raw_token, "refresh")
    except AppError:
        return
    record = db.scalar(select(RefreshToken).where(RefreshToken.jti == payload["jti"]))
    if record and record.revoked_at is None:
        record.revoked_at = datetime.now(timezone.utc)
        db.commit()


def request_password_reset(db: Session, email: str) -> str | None:
    user = db.scalar(select(User).where(func.lower(User.email) == normalize_email(email)))
    if user is None:
        return None
    raw, token_hash = create_reset_token()
    db.add(
        PasswordResetToken(
            user_id=user.id,
            token_hash=token_hash,
            expires_at=datetime.now(timezone.utc)
            + timedelta(minutes=settings.password_reset_minutes),
        )
    )
    db.commit()
    send_password_reset(user.email, raw)
    return raw


def reset_password(db: Session, token: str, new_password: str) -> None:
    token_hash = hash_reset_token(token)
    record = db.scalar(
        select(PasswordResetToken).where(PasswordResetToken.token_hash == token_hash)
    )
    now = datetime.now(timezone.utc)
    if record is None or record.used_at is not None or _as_utc(record.expires_at) <= now:
        raise AppError(400, "invalid_reset_token", "پیوند بازیابی نامعتبر یا منقضی شده است.")
    user = db.get(User, record.user_id)
    if user is None:
        raise AppError(404, "user_not_found", "کاربر یافت نشد.")
    user.password_hash = hash_password(new_password)
    record.used_at = now
    # Log out all current sessions after a password reset.
    for refresh in db.scalars(
        select(RefreshToken).where(
            RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None)
        )
    ):
        refresh.revoked_at = now
    db.commit()


def ensure_admin_user(db: Session) -> User:
    user = db.scalar(select(User).where(func.lower(User.email) == settings.admin_email.casefold()))
    if user:
        if user.role != "admin":
            user.role = "admin"
            db.commit()
        return user
    user = User(
        first_name="System",
        last_name="Administrator",
        username=settings.admin_username,
        email=settings.admin_email.casefold(),
        password_hash=hash_password(settings.admin_password.get_secret_value()),
        role="admin",
        is_active=True,
        bio="CineTrack system administrator",
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user
