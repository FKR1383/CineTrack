from __future__ import annotations

from collections import Counter
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import (
    Comment,
    CustomList,
    Episode,
    Favorite,
    Media,
    Rating,
    Season,
    User,
    UserEpisode,
    UserMedia,
)
from app.schemas.users import ProfileUpdateRequest


def update_profile(db: Session, user: User, data: ProfileUpdateRequest) -> User:
    updates = data.model_dump(exclude_unset=True)
    if "email" in updates and updates["email"] is not None:
        new_email = str(updates["email"]).strip().casefold()
        duplicate = db.scalar(
            select(User).where(func.lower(User.email) == new_email, User.id != user.id)
        )
        if duplicate:
            raise AppError(409, "duplicate_email", "این ایمیل قبلاً ثبت شده است.")
        updates["email"] = new_email
    if "username" in updates and updates["username"] is not None:
        new_username = updates["username"].strip()
        duplicate = db.scalar(
            select(User).where(
                func.lower(User.username) == new_username.casefold(), User.id != user.id
            )
        )
        if duplicate:
            raise AppError(409, "duplicate_username", "این نام کاربری قبلاً ثبت شده است.")
        updates["username"] = new_username
    for field, value in updates.items():
        if isinstance(value, str):
            value = value.strip()
        setattr(user, field, value)
    db.commit()
    db.refresh(user)
    return user


def user_stats(db: Session, user: User) -> dict[str, Any]:
    watched_movies = int(
        db.scalar(
            select(func.count(UserMedia.id))
            .join(Media, UserMedia.media_id == Media.id)
            .where(
                UserMedia.user_id == user.id,
                UserMedia.watch_status == "completed",
                Media.media_type == "movie",
            )
        )
        or 0
    )
    watched_series = int(
        db.scalar(
            select(func.count(UserMedia.id))
            .join(Media, UserMedia.media_id == Media.id)
            .where(
                UserMedia.user_id == user.id,
                UserMedia.watch_status == "completed",
                Media.media_type == "series",
            )
        )
        or 0
    )
    watched_episodes = int(
        db.scalar(
            select(func.count(UserEpisode.id)).where(
                UserEpisode.user_id == user.id, UserEpisode.watched.is_(True)
            )
        )
        or 0
    )
    movie_minutes = int(
        db.scalar(
            select(func.coalesce(func.sum(Media.runtime_minutes), 0))
            .join(UserMedia, UserMedia.media_id == Media.id)
            .where(
                UserMedia.user_id == user.id,
                UserMedia.watch_status == "completed",
                Media.media_type == "movie",
            )
        )
        or 0
    )
    episode_minutes = int(
        db.scalar(
            select(func.coalesce(func.sum(Episode.runtime_minutes), 0))
            .join(UserEpisode, UserEpisode.episode_id == Episode.id)
            .where(UserEpisode.user_id == user.id, UserEpisode.watched.is_(True))
        )
        or 0
    )
    completed_media = db.scalars(
        select(Media)
        .join(UserMedia, UserMedia.media_id == Media.id)
        .where(UserMedia.user_id == user.id, UserMedia.watch_status == "completed")
    ).all()
    favorite_media = db.scalars(
        select(Media).join(Favorite, Favorite.media_id == Media.id).where(Favorite.user_id == user.id)
    ).all()
    genre_counts: Counter[str] = Counter()
    for media in [*completed_media, *favorite_media]:
        genre_counts.update(media.genres or [])
    favorite_genre = genre_counts.most_common(1)[0][0] if genre_counts else None
    average_rating_raw = db.scalar(
        select(func.avg(Rating.score)).where(Rating.user_id == user.id)
    )
    favorites_count = int(
        db.scalar(select(func.count(Favorite.id)).where(Favorite.user_id == user.id)) or 0
    )
    custom_lists_count = int(
        db.scalar(select(func.count(CustomList.id)).where(CustomList.user_id == user.id)) or 0
    )
    total_minutes = movie_minutes + episode_minutes
    return {
        "watched_movies": watched_movies,
        "watched_series": watched_series,
        "watched_episodes": watched_episodes,
        "approximate_watch_minutes": total_minutes,
        "approximate_watch_hours": round(total_minutes / 60, 1),
        "favorite_genre": favorite_genre,
        "average_user_rating": round(float(average_rating_raw), 2)
        if average_rating_raw is not None
        else None,
        "favorites_count": favorites_count,
        "custom_lists_count": custom_lists_count,
    }


def user_activity(db: Session, user: User, limit: int = 100) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    for entry in db.scalars(
        select(UserMedia)
        .where(UserMedia.user_id == user.id)
        .order_by(UserMedia.updated_at.desc())
        .limit(limit)
    ).all():
        events.append(
            {
                "kind": "watch_status",
                "media_id": entry.media.media_key,
                "media_title": entry.media.title,
                "media_type": entry.media.media_type,
                "occurred_at": entry.updated_at,
                "detail": entry.watch_status,
            }
        )
    rating_rows = db.execute(
        select(Rating, Media)
        .join(Media, Rating.media_id == Media.id)
        .where(Rating.user_id == user.id)
        .order_by(Rating.updated_at.desc())
        .limit(limit)
    ).all()
    for rating, media in rating_rows:
        events.append(
            {
                "kind": "rating",
                "media_id": media.media_key,
                "media_title": media.title,
                "media_type": media.media_type,
                "occurred_at": rating.updated_at,
                "detail": str(rating.score),
            }
        )
    comment_rows = db.execute(
        select(Comment, Media)
        .join(Media, Comment.media_id == Media.id)
        .where(Comment.user_id == user.id)
        .order_by(Comment.created_at.desc())
        .limit(limit)
    ).all()
    for comment, media in comment_rows:
        events.append(
            {
                "kind": "comment",
                "media_id": media.media_key,
                "media_title": media.title,
                "media_type": media.media_type,
                "occurred_at": comment.created_at,
                "detail": "spoiler" if comment.is_spoiler else None,
            }
        )
    favorite_rows = db.execute(
        select(Favorite, Media)
        .join(Media, Favorite.media_id == Media.id)
        .where(Favorite.user_id == user.id)
        .order_by(Favorite.created_at.desc())
        .limit(limit)
    ).all()
    for favorite, media in favorite_rows:
        events.append(
            {
                "kind": "favorite",
                "media_id": media.media_key,
                "media_title": media.title,
                "media_type": media.media_type,
                "occurred_at": favorite.created_at,
                "detail": None,
            }
        )
    episode_rows = db.execute(
        select(UserEpisode, Episode, Season, Media)
        .join(Episode, UserEpisode.episode_id == Episode.id)
        .join(Season, Episode.season_id == Season.id)
        .join(Media, Season.media_id == Media.id)
        .where(UserEpisode.user_id == user.id, UserEpisode.watched.is_(True))
        .order_by(UserEpisode.updated_at.desc())
        .limit(limit)
    ).all()
    for marker, episode, season, media in episode_rows:
        events.append(
            {
                "kind": "episode",
                "media_id": media.media_key,
                "media_title": media.title,
                "media_type": media.media_type,
                "occurred_at": marker.updated_at,
                "detail": f"فصل {season.number}، قسمت {episode.number}: {episode.title}",
            }
        )
    for custom_list in db.scalars(
        select(CustomList)
        .where(CustomList.user_id == user.id)
        .order_by(CustomList.updated_at.desc())
        .limit(limit)
    ).all():
        events.append(
            {
                "kind": "custom_list",
                "media_id": "",
                "media_title": custom_list.name,
                "media_type": "",
                "occurred_at": custom_list.updated_at,
                "detail": "فهرست عمومی" if custom_list.is_public else "فهرست خصوصی",
            }
        )
    events.sort(key=lambda item: item["occurred_at"], reverse=True)
    items = events[:limit]
    return {"items": items, "total": len(events)}
