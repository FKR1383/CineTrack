from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Header, Query, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import FileResponse, JSONResponse

from app.core.deps import CurrentUser, DB, OptionalUser
from app.core.idempotency import get_saved_response, save_response
from app.schemas.admin import ReportCreateRequest
from app.schemas.common import PaginatedResponse
from app.schemas.media import (
    CommentCreateRequest,
    CommentResponse,
    CommentUpdateRequest,
    HomeSectionsResponse,
    MediaDetail,
    MediaSummary,
    SeasonResponse,
)
from app.services import admin as admin_service
from app.services import media as media_service
from app.services.posters import ensure_cached_poster

router = APIRouter(tags=["Media"])


@router.get("/media/provider-status")
def provider_status() -> dict:
    from app.config import get_settings

    settings = get_settings()
    return {
        "provider": settings.media_provider.lower(),
        "configured": settings.tmdb_configured,
        "live_search": settings.tmdb_search_live,
        "architecture": "Flutter -> CineTrack backend -> TMDB",
    }


@router.get("/media/home", response_model=HomeSectionsResponse)
def home(db: DB, current_user: OptionalUser) -> dict:
    return media_service.home_sections(db, current_user)


@router.get("/media/search", response_model=PaginatedResponse[MediaSummary])
def search(
    db: DB,
    q: str | None = Query(default=None, max_length=200),
    media_type: str | None = Query(default=None, pattern=r"^(movie|series)$"),
    actor: str | None = Query(default=None, max_length=120),
    director: str | None = Query(default=None, max_length=120),
    genre: str | None = Query(default=None, max_length=80),
    year: int | None = Query(default=None, ge=1870, le=2200),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=50),
) -> dict:
    items, pagination = media_service.search_media(
        db,
        query=q,
        media_type=media_type,
        actor=actor,
        director=director,
        genre=genre,
        year=year,
        page=page,
        page_size=page_size,
    )
    return {"items": items, "pagination": pagination}




@router.get("/media/{media_id}/poster", response_class=FileResponse)
def poster(media_id: str, db: DB) -> FileResponse:
    # Home/search rows already contain TMDB poster_path. Reuse that cached row
    # rather than triggering an expensive full-details TMDB call per poster.
    media = media_service.get_cached_media(db, media_id)
    if media is None or not media.poster_url:
        media = media_service.ensure_media(db, media_id)
    path = ensure_cached_poster(media)
    return FileResponse(
        path,
        media_type="image/webp",
        filename=f"{media_id}.webp",
        headers={
            "Cache-Control": "public, max-age=2592000, immutable",
            "X-Content-Type-Options": "nosniff",
        },
    )

@router.get("/media/{media_id}", response_model=MediaDetail)
def details(media_id: str, db: DB, current_user: OptionalUser) -> dict:
    media = media_service.ensure_media(db, media_id)
    return media_service.media_detail(db, media, current_user)


@router.get("/media/{media_id}/seasons", response_model=list[SeasonResponse])
def seasons(media_id: str, db: DB, current_user: OptionalUser) -> list[dict]:
    media = media_service.ensure_media(db, media_id)
    return media_service.seasons_for(db, current_user, media)


@router.get("/media/{media_id}/comments", response_model=PaginatedResponse[CommentResponse])
def comments(
    media_id: str,
    db: DB,
    current_user: OptionalUser,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=50),
) -> dict:
    media = media_service.ensure_media(db, media_id)
    items, pagination = media_service.comments_for(db, media, current_user, page, page_size)
    return {"items": items, "pagination": pagination}


@router.post(
    "/media/{media_id}/comments",
    response_model=CommentResponse,
    status_code=status.HTTP_201_CREATED,
)
def add_comment(
    media_id: str,
    data: CommentCreateRequest,
    db: DB,
    current_user: CurrentUser,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key", max_length=100)] = None,
):
    path = f"/media/{media_id}/comments"
    saved = get_saved_response(
        db, user=current_user, key=idempotency_key, method="POST", path=path
    )
    if saved:
        return JSONResponse(saved[1], status_code=saved[0])
    media = media_service.ensure_media(db, media_id)
    comment = media_service.create_comment(
        db, current_user, media, text=data.text, is_spoiler=data.is_spoiler
    )
    body = {
        "id": comment.id,
        "text": comment.text,
        "username": current_user.username,
        "user_avatar_url": current_user.avatar_url,
        "created_at": comment.created_at,
        "updated_at": comment.updated_at,
        "is_spoiler": comment.is_spoiler,
        "is_hidden": comment.is_hidden,
        "own_comment": True,
    }
    encoded = jsonable_encoder(body)
    save_response(
        db,
        user=current_user,
        key=idempotency_key,
        method="POST",
        path=path,
        status=201,
        body=encoded,
    )
    db.commit()
    return body


@router.patch("/comments/{comment_id}", response_model=CommentResponse)
def edit_comment(
    comment_id: str,
    data: CommentUpdateRequest,
    db: DB,
    current_user: CurrentUser,
) -> dict:
    comment = media_service.update_comment(
        db, current_user, comment_id, text=data.text, is_spoiler=data.is_spoiler
    )
    return {
        "id": comment.id,
        "text": comment.text,
        "username": comment.user.username,
        "user_avatar_url": comment.user.avatar_url,
        "created_at": comment.created_at,
        "updated_at": comment.updated_at,
        "is_spoiler": comment.is_spoiler,
        "is_hidden": comment.is_hidden,
        "own_comment": comment.user_id == current_user.id,
    }


@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_comment(comment_id: str, db: DB, current_user: CurrentUser) -> None:
    media_service.delete_comment(db, current_user, comment_id)


@router.post("/comments/{comment_id}/reports", status_code=status.HTTP_201_CREATED)
def report_comment(
    comment_id: str,
    data: ReportCreateRequest,
    db: DB,
    current_user: CurrentUser,
) -> dict:
    report = admin_service.report_comment(db, current_user, comment_id, data.reason)
    return {"id": report.id, "status": report.status, "message": "گزارش ثبت شد."}
