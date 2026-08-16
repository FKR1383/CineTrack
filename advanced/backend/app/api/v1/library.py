from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Header, Query, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse

from app.core.deps import CurrentUser, DB
from app.core.idempotency import get_saved_response, save_response
from app.schemas.common import MessageResponse, PaginatedResponse
from app.schemas.media import (
    EpisodeWatchRequest,
    LibraryEntry,
    ProgressResponse,
    RatingDistribution,
    RatingRequest,
    UserMediaState,
    WatchStatusRequest,
)
from app.services import media as media_service

router = APIRouter(prefix="/me", tags=["Personal library"])


@router.get("/library", response_model=PaginatedResponse[LibraryEntry])
def library(
    db: DB,
    current_user: CurrentUser,
    watch_status: str | None = Query(
        default=None,
        pattern=r"^(plan_to_watch|watching|completed|paused|dropped|favorite)$",
    ),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=50),
) -> dict:
    items, pagination = media_service.library_for(
        db, current_user, watch_status, page, page_size
    )
    return {"items": items, "pagination": pagination}


@router.put("/library/{media_id}", response_model=UserMediaState)
def update_library(
    media_id: str,
    data: WatchStatusRequest,
    db: DB,
    current_user: CurrentUser,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key", max_length=100)] = None,
):
    path = f"/me/library/{media_id}"
    saved = get_saved_response(
        db, user=current_user, key=idempotency_key, method="PUT", path=path
    )
    if saved:
        return JSONResponse(saved[1], status_code=saved[0])
    media = media_service.ensure_media(db, media_id)
    body = media_service.set_watch_status(db, current_user, media, data.status)
    encoded = jsonable_encoder(body)
    save_response(
        db,
        user=current_user,
        key=idempotency_key,
        method="PUT",
        path=path,
        status=200,
        body=encoded,
    )
    db.commit()
    return body


@router.delete("/library/{media_id}", response_model=MessageResponse)
def delete_library(media_id: str, db: DB, current_user: CurrentUser) -> MessageResponse:
    media = media_service.ensure_media(db, media_id)
    media_service.remove_library_entry(db, current_user, media)
    return MessageResponse(message="اثر از فهرست تماشا حذف شد.")


@router.put("/favorites/{media_id}", response_model=MessageResponse)
def favorite(media_id: str, db: DB, current_user: CurrentUser) -> MessageResponse:
    media = media_service.ensure_media(db, media_id)
    media_service.set_favorite(db, current_user, media, enabled=True)
    return MessageResponse(message="اثر به علاقه‌مندی‌ها افزوده شد.")


@router.delete("/favorites/{media_id}", response_model=MessageResponse)
def unfavorite(media_id: str, db: DB, current_user: CurrentUser) -> MessageResponse:
    media = media_service.ensure_media(db, media_id)
    media_service.set_favorite(db, current_user, media, enabled=False)
    return MessageResponse(message="اثر از علاقه‌مندی‌ها حذف شد.")


@router.put("/ratings/{media_id}", response_model=RatingDistribution)
def rate(
    media_id: str,
    data: RatingRequest,
    db: DB,
    current_user: CurrentUser,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key", max_length=100)] = None,
):
    path = f"/me/ratings/{media_id}"
    saved = get_saved_response(
        db, user=current_user, key=idempotency_key, method="PUT", path=path
    )
    if saved:
        return JSONResponse(saved[1], status_code=saved[0])
    media = media_service.ensure_media(db, media_id)
    body = media_service.set_rating(db, current_user, media, data.score)
    encoded = jsonable_encoder(body)
    save_response(
        db,
        user=current_user,
        key=idempotency_key,
        method="PUT",
        path=path,
        status=200,
        body=encoded,
    )
    db.commit()
    return body


@router.delete("/ratings/{media_id}", response_model=MessageResponse)
def unrate(media_id: str, db: DB, current_user: CurrentUser) -> MessageResponse:
    media = media_service.ensure_media(db, media_id)
    media_service.remove_rating(db, current_user, media)
    return MessageResponse(message="امتیاز حذف شد.")


@router.put("/episodes/{episode_id}", response_model=ProgressResponse)
def mark_episode(
    episode_id: str,
    data: EpisodeWatchRequest,
    db: DB,
    current_user: CurrentUser,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key", max_length=100)] = None,
):
    path = f"/me/episodes/{episode_id}"
    saved = get_saved_response(
        db, user=current_user, key=idempotency_key, method="PUT", path=path
    )
    if saved:
        return JSONResponse(saved[1], status_code=saved[0])
    body = media_service.set_episode_watched(
        db, current_user, episode_id, data.watched
    )
    encoded = jsonable_encoder(body)
    save_response(
        db,
        user=current_user,
        key=idempotency_key,
        method="PUT",
        path=path,
        status=200,
        body=encoded,
    )
    db.commit()
    return body


@router.get("/series/{media_id}/progress", response_model=ProgressResponse)
def progress(media_id: str, db: DB, current_user: CurrentUser) -> dict:
    media = media_service.ensure_media(db, media_id)
    media_service.ensure_episodes(db, media)
    return media_service.progress_for(db, current_user, media)
