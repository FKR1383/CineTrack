from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, File, Form, UploadFile, status

from app.config import get_settings
from app.core.deps import DB
from app.schemas.auth import (
    ForgotPasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenResponse,
)
from app.schemas.common import MessageResponse
from app.services import auth as auth_service
from app.services.uploads import remove_upload, save_profile_image

router = APIRouter(prefix="/auth", tags=["Authentication"])
settings = get_settings()


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    db: DB,
    first_name: Annotated[str, Form(min_length=1, max_length=80)],
    last_name: Annotated[str, Form(min_length=1, max_length=80)],
    username: Annotated[str, Form(min_length=3, max_length=40)],
    email: Annotated[str, Form()],
    password: Annotated[str, Form(min_length=8, max_length=128)],
    bio: Annotated[str | None, Form(max_length=500)] = None,
    profile_image: Annotated[UploadFile | None, File()] = None,
) -> TokenResponse:
    data = RegisterRequest(
        first_name=first_name,
        last_name=last_name,
        username=username,
        email=email,
        password=password,
        bio=bio,
    )
    avatar_url = await save_profile_image(profile_image) if profile_image else None
    try:
        user = auth_service.register_user(db, data, avatar_url)
    except Exception:
        remove_upload(avatar_url)
        raise
    return auth_service.issue_tokens(db, user, remember_me=True)


@router.post("/register-json", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_json(data: RegisterRequest, db: DB) -> TokenResponse:
    user = auth_service.register_user(db, data)
    return auth_service.issue_tokens(db, user, remember_me=True)


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, db: DB) -> TokenResponse:
    return auth_service.login(db, data)


@router.post("/refresh", response_model=TokenResponse)
def refresh(data: RefreshRequest, db: DB) -> TokenResponse:
    return auth_service.rotate_refresh_token(db, data.refresh_token, device_info=data.device_info)


@router.post("/logout", response_model=MessageResponse)
def logout(data: LogoutRequest, db: DB) -> MessageResponse:
    auth_service.logout(db, data.refresh_token)
    return MessageResponse(message="خروج از حساب با موفقیت انجام شد.")


@router.post("/password/forgot")
def forgot_password(data: ForgotPasswordRequest, db: DB) -> dict:
    raw_token = auth_service.request_password_reset(db, str(data.email))
    response: dict = {
        "message": "اگر این ایمیل ثبت شده باشد، راهنمای بازیابی ارسال می‌شود."
    }
    if not settings.is_production and raw_token:
        response["debug_reset_token"] = raw_token
    return response


@router.post("/password/reset", response_model=MessageResponse)
def reset_password(data: ResetPasswordRequest, db: DB) -> MessageResponse:
    auth_service.reset_password(db, data.token, data.new_password)
    return MessageResponse(message="رمز عبور تغییر کرد. لطفاً دوباره وارد شوید.")
