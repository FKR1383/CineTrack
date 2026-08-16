from __future__ import annotations

from datetime import datetime, timezone

import math

from fastapi import APIRouter, Query, status
from sqlalchemy import func, select

from app.core.deps import AdminUser, DB
from app.core.errors import AppError
from app.models import Comment, Media, Report, User
from app.schemas.admin import (
    AdminMediaUpdateRequest,
    AdminReportResponse,
    AdminStatsResponse,
    AdminUserUpdateRequest,
    ReportResolveRequest,
)
from app.schemas.auth import UserResponse
from app.schemas.common import MessageResponse, PaginatedResponse, PaginationMeta
from app.schemas.media import MediaSummary
from app.services import admin as admin_service
from app.services import media as media_service
from app.services.cache import get_cache
from app.services.posters import clear_cached_poster

router = APIRouter(prefix="/admin", tags=["Administration"])


@router.get("/stats", response_model=AdminStatsResponse)
def stats(db: DB, _: AdminUser) -> dict:
    return admin_service.system_stats(db)


@router.get("/users", response_model=PaginatedResponse[UserResponse])
def users(
    db: DB,
    _: AdminUser,
    q: str | None = Query(default=None, max_length=120),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
) -> dict:
    stmt = select(User)
    count_stmt = select(func.count(User.id))
    if q:
        pattern = f"%{q.casefold()}%"
        condition = (
            func.lower(User.username).like(pattern)
            | func.lower(User.email).like(pattern)
            | func.lower(User.first_name).like(pattern)
            | func.lower(User.last_name).like(pattern)
        )
        stmt = stmt.where(condition)
        count_stmt = count_stmt.where(condition)
    total = int(db.scalar(count_stmt) or 0)
    items = db.scalars(
        stmt.order_by(User.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    ).all()
    total_pages = math.ceil(total / page_size) if total else 0
    return {
        "items": [UserResponse.model_validate(item) for item in items],
        "pagination": PaginationMeta(
            page=page,
            page_size=page_size,
            total=total,
            total_pages=total_pages,
            has_next=page < total_pages,
            has_previous=page > 1,
        ),
    }


@router.patch("/users/{user_id}", response_model=UserResponse)
def update_user(
    user_id: str,
    data: AdminUserUpdateRequest,
    db: DB,
    admin: AdminUser,
) -> UserResponse:
    user = db.get(User, user_id)
    if user is None:
        raise AppError(404, "user_not_found", "کاربر پیدا نشد.")
    if user.id == admin.id and data.is_active is False:
        raise AppError(400, "cannot_disable_self", "مدیر نمی‌تواند حساب فعال خود را غیرفعال کند.")
    if user.id == admin.id and data.role == "user":
        raise AppError(400, "cannot_demote_self", "مدیر نمی‌تواند نقش مدیریتی حساب خود را حذف کند.")
    updates = data.model_dump(exclude_unset=True)
    for key, value in updates.items():
        setattr(user, key, value)
    db.commit()
    db.refresh(user)
    return UserResponse.model_validate(user)


@router.get("/reports", response_model=list[AdminReportResponse])
def reports(
    db: DB,
    _: AdminUser,
    report_status: str | None = Query(default=None, alias="status"),
) -> list[dict]:
    stmt = select(Report)
    if report_status:
        stmt = stmt.where(Report.status == report_status)
    rows = db.scalars(stmt.order_by(Report.created_at.desc()).limit(500)).all()
    return [admin_service.report_response(report) for report in rows]


@router.patch("/reports/{report_id}", response_model=AdminReportResponse)
def resolve_report(
    report_id: str,
    data: ReportResolveRequest,
    db: DB,
    _: AdminUser,
) -> dict:
    report = db.get(Report, report_id)
    if report is None:
        raise AppError(404, "report_not_found", "گزارش پیدا نشد.")
    report.status = data.status
    report.resolution_note = data.resolution_note
    db.commit()
    db.refresh(report)
    return admin_service.report_response(report)


@router.delete("/comments/{comment_id}", response_model=MessageResponse)
def delete_inappropriate_comment(
    comment_id: str, db: DB, _: AdminUser
) -> MessageResponse:
    comment = db.get(Comment, comment_id)
    if comment:
        db.delete(comment)
        db.commit()
    return MessageResponse(message="نظر نامناسب حذف شد.")


@router.get("/media", response_model=list[MediaSummary])
def cached_media(
    db: DB,
    _: AdminUser,
    media_type: str | None = Query(default=None, pattern=r"^(movie|series)$"),
    limit: int = Query(default=100, ge=1, le=500),
) -> list[dict]:
    stmt = select(Media)
    if media_type:
        stmt = stmt.where(Media.media_type == media_type)
    rows = db.scalars(stmt.order_by(Media.updated_at.desc()).limit(limit)).all()
    return media_service.media_summaries(db, rows)


@router.patch("/media/{media_id}", response_model=MediaSummary)
def update_cached_media(
    media_id: str,
    data: AdminMediaUpdateRequest,
    db: DB,
    _: AdminUser,
) -> dict:
    media = media_service.ensure_media(db, media_id)
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(media, key, value)
    db.commit()
    db.refresh(media)
    return media_service.media_summaries(db, [media])[0]


@router.post("/media/{media_id}/refresh", response_model=MediaSummary)
def refresh_cached_media(media_id: str, db: DB, _: AdminUser) -> dict:
    media = media_service.ensure_media(db, media_id, force=True)
    if media.media_type == "series":
        media_service.ensure_episodes(db, media, force=True)
    return media_service.media_summaries(db, [media])[0]


@router.delete("/media/{media_id}", response_model=MessageResponse)
def delete_cached_media(media_id: str, db: DB, _: AdminUser) -> MessageResponse:
    """Invalidate provider/cache data without deleting the Media row.

    UserMedia, ratings, comments, favourites, lists and watched episodes reference
    the stable Media row. Deleting that row would cascade-delete user history, so
    cache maintenance must only expire provider data and derived poster files.
    """
    media = db.scalar(select(Media).where(Media.media_key == media_id))
    if media:
        media.raw_payload = {}
        media.cached_at = datetime(1970, 1, 1, tzinfo=timezone.utc)
        clear_cached_poster(media)
        get_cache().delete("tmdb-home-sections:v3")
        db.commit()
    return MessageResponse(message="کش اثر پاک شد؛ امتیازها، نظرها، لیست‌ها و سوابق کاربران محفوظ ماند.")
