from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, File, UploadFile

from app.core.deps import CurrentUser, DB
from app.schemas.auth import UserResponse
from app.schemas.users import ActivityResponse, ProfileUpdateRequest, UserStatsResponse
from app.services.uploads import remove_upload, save_profile_image
from app.services.users import update_profile, user_activity, user_stats

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me", response_model=UserResponse)
def get_profile(current_user: CurrentUser) -> UserResponse:
    return UserResponse.model_validate(current_user)


@router.patch("/me", response_model=UserResponse)
def patch_profile(
    data: ProfileUpdateRequest, db: DB, current_user: CurrentUser
) -> UserResponse:
    return UserResponse.model_validate(update_profile(db, current_user, data))


@router.post("/me/avatar", response_model=UserResponse)
async def upload_avatar(
    db: DB,
    current_user: CurrentUser,
    profile_image: Annotated[UploadFile, File()],
) -> UserResponse:
    new_url = await save_profile_image(profile_image)
    old_url = current_user.avatar_url
    current_user.avatar_url = new_url
    db.commit()
    db.refresh(current_user)
    remove_upload(old_url)
    return UserResponse.model_validate(current_user)


@router.delete("/me/avatar", response_model=UserResponse)
def delete_avatar(db: DB, current_user: CurrentUser) -> UserResponse:
    old_url = current_user.avatar_url
    current_user.avatar_url = None
    db.commit()
    db.refresh(current_user)
    remove_upload(old_url)
    return UserResponse.model_validate(current_user)


@router.get("/me/stats", response_model=UserStatsResponse)
def get_stats(db: DB, current_user: CurrentUser) -> dict:
    return user_stats(db, current_user)


@router.get("/me/activity", response_model=ActivityResponse)
def get_activity(
    db: DB, current_user: CurrentUser, limit: int = 100
) -> dict:
    return user_activity(db, current_user, min(max(limit, 1), 200))
