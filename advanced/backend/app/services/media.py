from __future__ import annotations

import hashlib
import json
import math
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.core.errors import AppError
from app.models import (
    Comment,
    Episode,
    Favorite,
    Media,
    Rating,
    Season,
    User,
    UserEpisode,
    UserMedia,
)
from app.schemas.common import PaginationMeta
from app.services.cache import get_cache
from app.services.posters import public_poster_url
from app.services.providers.base import (
    MediaNotFoundError,
    MediaProviderConfigurationError,
    MediaProviderUnavailableError,
)
from app.services.providers.factory import get_media_provider

settings = get_settings()


def _parse_date(value: Any) -> date | None:
    if value is None or isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _fresh(cached_at: datetime, ttl: int) -> bool:
    if cached_at.tzinfo is None:
        cached_at = cached_at.replace(tzinfo=timezone.utc)
    return cached_at >= datetime.now(timezone.utc) - timedelta(seconds=ttl)


def seed_provider_catalog(db: Session) -> int:
    """Populate the server cache from real TMDB discovery endpoints.

    No hard-coded/demo movie catalog exists in the production path. If TMDB is
    temporarily unavailable and cached records already exist, startup can still
    proceed using those records.
    """
    try:
        sections = get_media_provider().home_sections()
    except MediaProviderUnavailableError:
        existing = int(
            db.scalar(select(func.count(Media.id)).where(Media.provider == "tmdb")) or 0
        )
        if existing:
            return 0
        raise

    seen: set[str] = set()
    added = 0
    for payloads in sections.values():
        for payload in payloads:
            key = str(payload.get("media_key") or "")
            if not key or key in seen:
                continue
            seen.add(key)
            existing = db.scalar(select(Media).where(Media.media_key == key))
            media = upsert_media(db, payload, commit=False)
            if existing is None and media.created_at == media.updated_at:
                added += 1
    db.commit()
    return added


def upsert_media(db: Session, payload: dict[str, Any], *, commit: bool = True) -> Media:
    media_key = str(payload.get("media_key") or "").strip()
    provider = str(payload.get("provider") or "tmdb").strip().lower()
    provider_id = str(payload.get("provider_id") or "").strip() or None
    media_type = "series" if payload.get("media_type") == "series" else "movie"
    if not media_key:
        raise ValueError("Provider payload has no media_key")

    media = db.scalar(select(Media).where(Media.media_key == media_key))
    if media is None and provider_id:
        media = db.scalar(
            select(Media).where(
                Media.provider == provider,
                Media.media_type == media_type,
                Media.provider_id == provider_id,
            )
        )
    if media is None:
        media = Media(media_key=media_key, media_type=media_type, title="")
        db.add(media)

    media.provider = provider
    media.provider_id = provider_id
    media.tmdb_id = payload.get("tmdb_id")
    media.external_imdb_id = payload.get("imdb_id") or media.external_imdb_id
    media.media_type = media_type
    media.title = str(payload.get("title") or media_key)[:500]
    media.original_title = payload.get("original_title") or None
    # Keep the upstream URL server-side only. Flutter receives public_poster_url().
    if "poster_source_url" in payload:
        media.poster_url = payload.get("poster_source_url") or None
    media.plot = payload.get("plot") or None
    media.genres = [str(x) for x in (payload.get("genres") or []) if x]
    media.release_year = payload.get("release_year")
    media.end_year = payload.get("end_year")
    media.release_date = _parse_date(payload.get("release_date"))
    media.runtime_minutes = payload.get("runtime_minutes")
    media.countries = [str(x) for x in (payload.get("countries") or []) if x]
    media.directors = [str(x) for x in (payload.get("directors") or []) if x]
    media.cast = [str(x) for x in (payload.get("cast") or []) if x]
    media.provider_rating = payload.get("provider_rating")
    media.provider_vote_count = payload.get("provider_vote_count")
    media.release_status = payload.get("release_status")
    if payload.get("season_count") is not None:
        media.season_count = int(payload["season_count"])
    if payload.get("episode_count") is not None:
        media.episode_count = int(payload["episode_count"])
    media.raw_payload = payload.get("raw_payload") or payload
    media.cached_at = datetime.now(timezone.utc)
    if commit:
        db.commit()
        db.refresh(media)
    return media


def upsert_episodes(
    db: Session, media: Media, episodes_payload: list[dict[str, Any]], *, commit: bool = True
) -> None:
    season_map = {season.number: season for season in media.seasons}
    seen_counts: Counter[int] = Counter()
    for item in episodes_payload:
        season_number = int(item.get("season_number") or 0)
        episode_number = int(item.get("episode_number") or 0)
        episode_key = str(item.get("episode_key") or "").strip()
        if season_number < 1 or episode_number < 1 or not episode_key:
            continue
        season = season_map.get(season_number)
        if season is None:
            season = Season(
                media_id=media.id,
                number=season_number,
                title=f"Season {season_number}",
                episode_count=0,
            )
            db.add(season)
            db.flush()
            season_map[season_number] = season
        episode = db.scalar(select(Episode).where(Episode.episode_key == episode_key))
        if episode is None:
            episode = Episode(
                season_id=season.id,
                episode_key=episode_key,
                number=episode_number,
                title=str(item.get("title") or f"Episode {episode_number}"),
            )
            db.add(episode)
        else:
            episode.season_id = season.id
            episode.number = episode_number
        episode.provider = str(item.get("provider") or "tmdb")
        episode.provider_id = str(item.get("provider_id") or "") or None
        episode.tmdb_id = item.get("tmdb_id")
        episode.external_imdb_id = item.get("imdb_id") or episode.external_imdb_id
        episode.title = str(item.get("title") or f"Episode {episode_number}")[:500]
        episode.release_date = _parse_date(item.get("release_date"))
        episode.runtime_minutes = item.get("runtime_minutes")
        episode.plot = item.get("plot") or None
        seen_counts[season_number] += 1
    for number, season in season_map.items():
        season.episode_count = seen_counts.get(number, season.episode_count)
    if seen_counts:
        media.season_count = len([number for number in season_map if number > 0])
        media.episode_count = sum(seen_counts.values())
    media.cached_at = datetime.now(timezone.utc)
    if commit:
        db.commit()


def _has_full_detail(media: Media) -> bool:
    raw = media.raw_payload or {}
    if media.media_type == "movie":
        return isinstance(raw.get("credits"), dict)
    return isinstance(raw.get("aggregate_credits"), dict)


def get_cached_media(db: Session, media_id: str) -> Media | None:
    """Return a locally cached row without triggering a provider detail request.

    Poster requests use this so rendering a home grid does not fan out into one
    TMDB details API call per image.
    """
    return db.scalar(select(Media).where(Media.media_key == media_id))


def ensure_media(db: Session, media_id: str, *, force: bool = False) -> Media:
    media = get_cached_media(db, media_id)
    # Search/home endpoints only return summary payloads. Opening a details page
    # must still call the TMDB details endpoint at least once so cast, directors,
    # runtime, countries, status and external IDs are complete.
    is_fresh_tmdb = bool(
        media
        and media.provider == "tmdb"
        and _has_full_detail(media)
        and not force
        and _fresh(media.cached_at, settings.media_cache_ttl_seconds)
    )
    if is_fresh_tmdb:
        return media
    try:
        payload = get_media_provider().get_title(media_id)
        if media is not None and media.provider != "tmdb":
            payload = dict(payload)
            payload["media_key"] = media.media_key
        return upsert_media(db, payload)
    except MediaNotFoundError as exc:
        if media:
            return media
        raise AppError(404, "media_not_found", "فیلم یا سریال موردنظر پیدا نشد.") from exc
    except (MediaProviderUnavailableError, MediaProviderConfigurationError) as exc:
        if media:
            return media
        raise AppError(
            503,
            "provider_unavailable",
            "سرویس اطلاعات فیلم و سریال در دسترس نیست.",
            detail="TMDB is unavailable and no usable cached copy exists for this title.",
        ) from exc


def ensure_episodes(db: Session, media: Media, *, force: bool = False) -> None:
    if media.media_type != "series":
        return
    count = db.scalar(
        select(func.count(Episode.id)).join(Season).where(Season.media_id == media.id)
    ) or 0
    if count and not force and _fresh(media.cached_at, settings.media_cache_ttl_seconds):
        return
    try:
        payload = get_media_provider().get_episodes(media.media_key)
        if payload:
            upsert_episodes(db, media, payload)
        elif count == 0:
            media.episode_count = media.episode_count or 0
            db.commit()
    except (MediaProviderUnavailableError, MediaProviderConfigurationError) as exc:
        if count:
            return
        raise AppError(
            503,
            "provider_unavailable",
            "دریافت فصل‌ها و قسمت‌ها با خطا مواجه شد.",
            detail="TMDB is unavailable and no cached episodes exist.",
        ) from exc


def _rating_stats(db: Session, media_ids: list[str]) -> dict[str, tuple[float | None, int]]:
    if not media_ids:
        return {}
    rows = db.execute(
        select(Rating.media_id, func.avg(Rating.score), func.count(Rating.id))
        .where(Rating.media_id.in_(media_ids))
        .group_by(Rating.media_id)
    ).all()
    return {
        media_id: (round(float(avg), 2) if avg is not None else None, int(count))
        for media_id, avg, count in rows
    }


def media_summaries(db: Session, media_list: list[Media]) -> list[dict[str, Any]]:
    stats = _rating_stats(db, [media.id for media in media_list])
    result: list[dict[str, Any]] = []
    for media in media_list:
        app_rating, rating_count = stats.get(media.id, (None, 0))
        result.append(
            {
                "media_id": media.media_key,
                "provider": media.provider,
                "tmdb_id": media.tmdb_id,
                "imdb_id": media.external_imdb_id,
                "media_type": media.media_type,
                "title": media.title,
                "original_title": media.original_title,
                "poster_url": public_poster_url(media),
                "plot": media.plot,
                "genres": media.genres or [],
                "release_year": media.release_year,
                "end_year": media.end_year,
                "provider_rating": media.provider_rating,
                "app_rating": app_rating,
                "rating_count": rating_count,
                "release_status": media.release_status,
                "season_count": media.season_count,
                "episode_count": media.episode_count,
            }
        )
    return result


def rating_distribution(db: Session, media: Media) -> dict[str, Any]:
    rows = db.execute(
        select(Rating.score, func.count(Rating.id))
        .where(Rating.media_id == media.id)
        .group_by(Rating.score)
    ).all()
    counts = {score: 0 for score in range(1, 6)}
    for score, count in rows:
        counts[int(score)] = int(count)
    total = sum(counts.values())
    percentages = {
        score: round((count / total * 100), 1) if total else 0.0
        for score, count in counts.items()
    }
    return {"total": total, "counts": counts, "percentages": percentages}


def progress_for(db: Session, user: User, media: Media) -> dict[str, Any]:
    cached_episode_total = int(
        db.scalar(
            select(func.count(Episode.id)).join(Season).where(Season.media_id == media.id)
        )
        or 0
    )
    total = max(cached_episode_total, int(media.episode_count or 0))
    watched = int(
        db.scalar(
            select(func.count(UserEpisode.id))
            .join(Episode, UserEpisode.episode_id == Episode.id)
            .join(Season, Episode.season_id == Season.id)
            .where(
                UserEpisode.user_id == user.id,
                UserEpisode.watched.is_(True),
                Season.media_id == media.id,
            )
        )
        or 0
    )
    remaining = max(total - watched, 0)
    percent = round((watched / total * 100), 1) if total else 0.0
    user_media = db.scalar(
        select(UserMedia).where(UserMedia.user_id == user.id, UserMedia.media_id == media.id)
    )
    status = user_media.watch_status if user_media else None
    ongoing = (media.release_status or "").casefold() in {
        "ongoing",
        "returning",
        "in_production",
        "active",
    }
    if status in {"paused", "dropped"} and watched < total:
        color, hex_value = "red", "#C62828"
    elif total == 0 or watched == 0:
        color, hex_value = "black", "#212121"
    elif watched >= total and ongoing:
        color, hex_value = "green", "#2E7D32"
    elif watched >= total:
        color, hex_value = "purple", "#7B1FA2"
    else:
        color, hex_value = "yellow", "#F9A825"
    return {
        "media_id": media.media_key,
        "watched_episodes": watched,
        "total_episodes": total,
        "remaining_episodes": remaining,
        "progress_percent": percent,
        "progress_color": color,
        "progress_hex": hex_value,
        "release_status": media.release_status,
    }


def user_state(db: Session, user: User, media: Media) -> dict[str, Any]:
    entry = db.scalar(
        select(UserMedia).where(UserMedia.user_id == user.id, UserMedia.media_id == media.id)
    )
    favorite = db.scalar(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.media_id == media.id)
    )
    rating = db.scalar(
        select(Rating).where(Rating.user_id == user.id, Rating.media_id == media.id)
    )
    progress = progress_for(db, user, media) if media.media_type == "series" else None
    return {
        "watch_status": entry.watch_status if entry else None,
        "is_favorite": favorite is not None,
        "user_rating": rating.score if rating else None,
        "watched_episodes": progress["watched_episodes"] if progress else 0,
        "remaining_episodes": progress["remaining_episodes"] if progress else 0,
        "progress_percent": progress["progress_percent"] if progress else 0,
        "progress_color": progress["progress_color"] if progress else "black",
        "progress_hex": progress["progress_hex"] if progress else "#212121",
    }


def media_detail(db: Session, media: Media, user: User | None) -> dict[str, Any]:
    # Do not download all TV episodes just to render the top of the details page.
    # Seasons/episodes are fetched by the dedicated endpoint in parallel.
    summary = media_summaries(db, [media])[0]
    return {
        **summary,
        "release_date": media.release_date,
        "runtime_minutes": media.runtime_minutes,
        "countries": media.countries or [],
        "directors": media.directors or [],
        "cast": media.cast or [],
        "provider_vote_count": media.provider_vote_count,
        "rating_distribution": rating_distribution(db, media),
        "user_state": user_state(db, user, media) if user else None,
        "cached_at": media.cached_at,
    }


def _matches(media: Media, actor: str | None, director: str | None, genre: str | None) -> bool:
    if actor and actor.casefold() not in " ".join(media.cast or []).casefold():
        return False
    if director and director.casefold() not in " ".join(media.directors or []).casefold():
        return False
    if genre and genre.casefold() not in " ".join(media.genres or []).casefold():
        return False
    return True


def _local_search_fallback(
    db: Session,
    *,
    query: str | None,
    media_type: str | None,
    actor: str | None,
    director: str | None,
    genre: str | None,
    year: int | None,
    page: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], PaginationMeta]:
    statement = select(Media).where(Media.provider == "tmdb")
    if media_type:
        statement = statement.where(Media.media_type == media_type)
    if year:
        statement = statement.where(Media.release_year == year)
    if query:
        lowered = f"%{query.casefold()}%"
        statement = statement.where(
            or_(
                func.lower(Media.title).like(lowered),
                func.lower(Media.original_title).like(lowered),
            )
        )
    statement = statement.order_by(
        Media.provider_vote_count.desc().nullslast(),
        Media.provider_rating.desc().nullslast(),
        Media.title,
    )
    candidates = [m for m in db.scalars(statement).all() if _matches(m, actor, director, genre)]
    total = len(candidates)
    start = (page - 1) * page_size
    page_items = candidates[start : start + page_size]
    total_pages = math.ceil(total / page_size) if total else 0
    return media_summaries(db, page_items), PaginationMeta(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_next=page < total_pages,
        has_previous=page > 1,
    )


def search_media(
    db: Session,
    *,
    query: str | None,
    media_type: str | None,
    actor: str | None,
    director: str | None,
    genre: str | None,
    year: int | None,
    page: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], PaginationMeta]:
    """Run a real TMDB search, persist normalized results, and cache only as fallback."""
    query = query.strip() if query else None
    actor = actor.strip() if actor else None
    director = director.strip() if director else None
    genre = genre.strip() if genre else None
    if not any([query, media_type, actor, director, genre, year]):
        return [], PaginationMeta(
            page=page,
            page_size=page_size,
            total=0,
            total_pages=0,
            has_next=False,
            has_previous=page > 1,
        )

    key_data = {
        "q": query,
        "type": media_type,
        "actor": actor,
        "director": director,
        "genre": genre,
        "year": year,
        "page": page,
        "page_size": page_size,
    }
    key = "tmdb-search:" + hashlib.sha256(
        json.dumps(key_data, sort_keys=True).encode("utf-8")
    ).hexdigest()
    cached = get_cache().get_json(key)

    if cached and not settings.tmdb_search_live:
        payload = cached
    else:
        try:
            result = get_media_provider().search(
                query=query,
                media_type=media_type,
                actor=actor,
                director=director,
                genre=genre,
                year=year,
                page=page,
                page_size=page_size,
            )
            payload = {
                "items": result.items,
                "page": result.page,
                "page_size": result.page_size,
                "total": result.total,
                "total_pages": result.total_pages,
            }
            get_cache().set_json(key, payload, settings.search_cache_ttl_seconds)
        except (MediaProviderUnavailableError, MediaProviderConfigurationError) as exc:
            if cached:
                payload = cached
            else:
                items, meta = _local_search_fallback(
                    db,
                    query=query,
                    media_type=media_type,
                    actor=actor,
                    director=director,
                    genre=genre,
                    year=year,
                    page=page,
                    page_size=page_size,
                )
                if items:
                    return items, meta
                raise AppError(
                    503,
                    "provider_unavailable",
                    "دریافت نتایج جست‌وجو با خطا مواجه شد.",
                    detail="TMDB is unavailable and no cached search result exists.",
                ) from exc

    media_rows: list[Media] = []
    for item in payload.get("items") or []:
        media_rows.append(upsert_media(db, item, commit=False))
    if media_rows:
        db.commit()
        for media in media_rows:
            db.refresh(media)

    total = int(payload.get("total") or len(media_rows))
    total_pages = int(payload.get("total_pages") or (math.ceil(total / page_size) if total else 0))
    meta = PaginationMeta(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_next=page < total_pages,
        has_previous=page > 1,
    )
    return media_summaries(db, media_rows), meta


def seasons_for(db: Session, user: User | None, media: Media) -> list[dict[str, Any]]:
    ensure_episodes(db, media)
    seasons = db.scalars(select(Season).where(Season.media_id == media.id).order_by(Season.number)).all()
    watched_ids: set[str] = set()
    if user:
        watched_ids = set(
            db.scalars(
                select(UserEpisode.episode_id).where(
                    UserEpisode.user_id == user.id, UserEpisode.watched.is_(True)
                )
            ).all()
        )
    return [
        {
            "season_number": season.number,
            "title": season.title,
            "episode_count": season.episode_count,
            "episodes": [
                {
                    "episode_id": episode.episode_key,
                    "provider": episode.provider,
                    "tmdb_id": episode.tmdb_id,
                    "imdb_id": episode.external_imdb_id,
                    "season_number": season.number,
                    "episode_number": episode.number,
                    "title": episode.title,
                    "release_date": episode.release_date,
                    "runtime_minutes": episode.runtime_minutes,
                    "plot": episode.plot,
                    "watched": episode.id in watched_ids,
                }
                for episode in season.episodes
            ],
        }
        for season in seasons
    ]


def set_watch_status(db: Session, user: User, media: Media, status: str) -> dict[str, Any]:
    if status == "favorite":
        set_favorite(db, user, media, enabled=True)
        return user_state(db, user, media)
    now = datetime.now(timezone.utc)
    entry = db.scalar(
        select(UserMedia).where(UserMedia.user_id == user.id, UserMedia.media_id == media.id)
    )
    if entry is None:
        entry = UserMedia(user_id=user.id, media_id=media.id)
        db.add(entry)
    entry.watch_status = status
    if status == "watching" and entry.started_at is None:
        entry.started_at = now
    if status == "completed":
        entry.completed_at = now
        if media.media_type == "series":
            ensure_episodes(db, media)
            episode_ids = list(
                db.scalars(
                    select(Episode.id).join(Season).where(Season.media_id == media.id)
                ).all()
            )
            existing = {
                item.episode_id: item
                for item in db.scalars(
                    select(UserEpisode).where(
                        UserEpisode.user_id == user.id,
                        UserEpisode.episode_id.in_(episode_ids),
                    )
                ).all()
            }
            for episode_id in episode_ids:
                marker = existing.get(episode_id)
                if marker is None:
                    db.add(
                        UserEpisode(
                            user_id=user.id,
                            episode_id=episode_id,
                            watched=True,
                            watched_at=now,
                        )
                    )
                else:
                    marker.watched = True
                    marker.watched_at = now
    elif status != "completed":
        entry.completed_at = None
    db.commit()
    return user_state(db, user, media)


def remove_library_entry(db: Session, user: User, media: Media) -> None:
    entry = db.scalar(
        select(UserMedia).where(UserMedia.user_id == user.id, UserMedia.media_id == media.id)
    )
    if entry:
        db.delete(entry)
        db.commit()


def set_favorite(db: Session, user: User, media: Media, *, enabled: bool) -> bool:
    favorite = db.scalar(
        select(Favorite).where(Favorite.user_id == user.id, Favorite.media_id == media.id)
    )
    if enabled and favorite is None:
        db.add(Favorite(user_id=user.id, media_id=media.id))
    elif not enabled and favorite is not None:
        db.delete(favorite)
    db.commit()
    return enabled


def set_rating(db: Session, user: User, media: Media, score: int) -> dict[str, Any]:
    rating = db.scalar(
        select(Rating).where(Rating.user_id == user.id, Rating.media_id == media.id)
    )
    if rating is None:
        rating = Rating(user_id=user.id, media_id=media.id, score=score)
        db.add(rating)
    else:
        rating.score = score
    db.commit()
    return rating_distribution(db, media)


def remove_rating(db: Session, user: User, media: Media) -> None:
    rating = db.scalar(
        select(Rating).where(Rating.user_id == user.id, Rating.media_id == media.id)
    )
    if rating:
        db.delete(rating)
        db.commit()


def set_episode_watched(db: Session, user: User, episode_id: str, watched: bool) -> dict[str, Any]:
    episode = db.scalar(select(Episode).where(Episode.episode_key == episode_id))
    if episode is None:
        raise AppError(404, "episode_not_found", "قسمت موردنظر پیدا نشد.")
    item = db.scalar(
        select(UserEpisode).where(
            UserEpisode.user_id == user.id, UserEpisode.episode_id == episode.id
        )
    )
    now = datetime.now(timezone.utc)
    if watched:
        if item is None:
            item = UserEpisode(
                user_id=user.id,
                episode_id=episode.id,
                watched=True,
                watched_at=now,
            )
            db.add(item)
        else:
            item.watched = True
            item.watched_at = now
    elif item is not None:
        # An unwatched episode is represented by the absence of a marker.
        db.delete(item)

    season = db.get(Season, episode.season_id)
    media = db.get(Media, season.media_id) if season else None
    if media is None:
        raise AppError(404, "media_not_found", "سریال مربوط به قسمت یافت نشد.")
    entry = db.scalar(
        select(UserMedia).where(UserMedia.user_id == user.id, UserMedia.media_id == media.id)
    )
    if entry is None and watched:
        entry = UserMedia(user_id=user.id, media_id=media.id, watch_status="watching")
        db.add(entry)
    elif entry is not None:
        if watched and entry.watch_status in {None, "plan_to_watch"}:
            entry.watch_status = "watching"
        elif not watched and entry.watch_status == "completed":
            entry.watch_status = "watching"
            entry.completed_at = None

    db.commit()
    progress = progress_for(db, user, media)
    if watched and progress["total_episodes"] and progress["remaining_episodes"] == 0:
        if entry is None:
            entry = UserMedia(user_id=user.id, media_id=media.id)
            db.add(entry)
        entry.watch_status = "completed"
        entry.completed_at = now
        db.commit()
        progress = progress_for(db, user, media)
    return progress


def create_comment(
    db: Session, user: User, media: Media, *, text: str, is_spoiler: bool
) -> Comment:
    comment = Comment(
        user_id=user.id,
        media_id=media.id,
        text=text.strip(),
        is_spoiler=is_spoiler,
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return comment


def update_comment(
    db: Session, user: User, comment_id: str, *, text: str, is_spoiler: bool
) -> Comment:
    comment = db.get(Comment, comment_id)
    if comment is None or comment.is_hidden:
        raise AppError(404, "comment_not_found", "نظر پیدا نشد.")
    if comment.user_id != user.id and user.role != "admin":
        raise AppError(403, "not_comment_owner", "فقط نویسنده نظر می‌تواند آن را ویرایش کند.")
    comment.text = text.strip()
    comment.is_spoiler = is_spoiler
    db.commit()
    db.refresh(comment)
    return comment


def delete_comment(db: Session, user: User, comment_id: str) -> None:
    comment = db.get(Comment, comment_id)
    if comment is None:
        return
    if comment.user_id != user.id and user.role != "admin":
        raise AppError(403, "not_comment_owner", "اجازه حذف این نظر را ندارید.")
    db.delete(comment)
    db.commit()


def comments_for(
    db: Session, media: Media, user: User | None, page: int, page_size: int
) -> tuple[list[dict[str, Any]], PaginationMeta]:
    base = select(Comment).where(Comment.media_id == media.id, Comment.is_hidden.is_(False))
    total = int(
        db.scalar(
            select(func.count(Comment.id)).where(
                Comment.media_id == media.id, Comment.is_hidden.is_(False)
            )
        )
        or 0
    )
    comments = db.scalars(
        base.order_by(Comment.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    ).all()
    items = [
        {
            "id": comment.id,
            "text": comment.text,
            "username": comment.user.username,
            "user_avatar_url": comment.user.avatar_url,
            "created_at": comment.created_at,
            "updated_at": comment.updated_at,
            "is_spoiler": comment.is_spoiler,
            "is_hidden": comment.is_hidden,
            "own_comment": bool(user and comment.user_id == user.id),
        }
        for comment in comments
    ]
    total_pages = math.ceil(total / page_size) if total else 0
    return items, PaginationMeta(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_next=page < total_pages,
        has_previous=page > 1,
    )


def library_for(
    db: Session, user: User, status: str | None, page: int, page_size: int
) -> tuple[list[dict[str, Any]], PaginationMeta]:
    if status == "favorite":
        media_rows = db.scalars(
            select(Media)
            .join(Favorite, Favorite.media_id == Media.id)
            .where(Favorite.user_id == user.id)
            .order_by(Favorite.created_at.desc())
        ).all()
        entries_by_media: dict[str, UserMedia] = {
            item.media_id: item
            for item in db.scalars(select(UserMedia).where(UserMedia.user_id == user.id)).all()
        }
    else:
        stmt = select(UserMedia).where(UserMedia.user_id == user.id)
        if status:
            stmt = stmt.where(UserMedia.watch_status == status)
        entries = db.scalars(stmt.order_by(UserMedia.updated_at.desc())).all()
        media_rows = [entry.media for entry in entries]
        entries_by_media = {entry.media_id: entry for entry in entries}
    total = len(media_rows)
    selected = media_rows[(page - 1) * page_size : page * page_size]
    summary_map = {
        item["media_id"]: item for item in media_summaries(db, selected)
    }
    favorite_ids = set(
        db.scalars(select(Favorite.media_id).where(Favorite.user_id == user.id)).all()
    )
    items = []
    for media in selected:
        entry = entries_by_media.get(media.id)
        items.append(
            {
                "media": summary_map[media.media_key],
                "watch_status": entry.watch_status if entry else None,
                "is_favorite": media.id in favorite_ids,
                "progress": progress_for(db, user, media) if media.media_type == "series" else None,
                "updated_at": entry.updated_at if entry else datetime.now(timezone.utc),
            }
        )
    total_pages = math.ceil(total / page_size) if total else 0
    return items, PaginationMeta(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_next=page < total_pages,
        has_previous=page > 1,
    )


def _top_media(db: Session, where_type: str | None, order_by: Any, limit: int = 12) -> list[Media]:
    stmt = select(Media).where(Media.provider == "tmdb")
    if where_type:
        stmt = stmt.where(Media.media_type == where_type)
    return db.scalars(stmt.order_by(order_by).limit(limit)).all()


def recommendations_for(db: Session, user: User | None, limit: int = 12) -> list[Media]:
    all_media = db.scalars(select(Media).where(Media.provider == "tmdb")).all()
    if user is None:
        return sorted(
            all_media,
            key=lambda m: (m.provider_rating or 0, m.provider_vote_count or 0),
            reverse=True,
        )[:limit]
    preferred: Counter[str] = Counter()
    favorite_media = db.scalars(
        select(Media)
        .join(Favorite, Favorite.media_id == Media.id)
        .where(Favorite.user_id == user.id, Media.provider == "tmdb")
    ).all()
    highly_rated = db.scalars(
        select(Media)
        .join(Rating, Rating.media_id == Media.id)
        .where(Rating.user_id == user.id, Rating.score >= 4, Media.provider == "tmdb")
    ).all()
    for media in [*favorite_media, *highly_rated]:
        preferred.update(media.genres or [])
    excluded = set(
        db.scalars(select(UserMedia.media_id).where(UserMedia.user_id == user.id)).all()
    )
    excluded.update(
        db.scalars(select(Favorite.media_id).where(Favorite.user_id == user.id)).all()
    )

    def score(media: Media) -> tuple[float, float, int]:
        genre_score = sum(preferred[g] for g in (media.genres or []))
        return (
            float(genre_score),
            float(media.provider_rating or 0),
            int(media.provider_vote_count or 0),
        )

    candidates = [media for media in all_media if media.id not in excluded]
    return sorted(candidates, key=score, reverse=True)[:limit]


def _refresh_home_from_tmdb(db: Session) -> dict[str, list[str]] | None:
    """Refresh real TMDB home sections and preserve their ordering.

    The previous implementation persisted titles but then rebuilt "popular" from
    vote counts, losing TMDB's actual popular/trending ordering.  This stores the
    section media keys in Redis while normalized Media rows remain in PostgreSQL.
    """
    cache = get_cache()
    cache_key = "tmdb-home-sections:v3"
    cached = cache.get_json(cache_key)
    if isinstance(cached, dict) and cached:
        return {
            name: [str(key) for key in keys]
            for name, keys in cached.items()
            if isinstance(keys, list)
        }
    try:
        sections = get_media_provider().home_sections()
    except (MediaProviderUnavailableError, MediaProviderConfigurationError):
        return None

    section_keys: dict[str, list[str]] = {}
    changed = False
    for name, items in sections.items():
        keys: list[str] = []
        for payload in items:
            media = upsert_media(db, payload, commit=False)
            keys.append(media.media_key)
            changed = True
        section_keys[name] = keys
    if changed:
        db.commit()
    cache.set_json(cache_key, section_keys, settings.home_cache_ttl_seconds)
    return section_keys


def _media_in_key_order(db: Session, keys: list[str] | None) -> list[Media]:
    if not keys:
        return []
    rows = db.scalars(select(Media).where(Media.media_key.in_(keys))).all()
    by_key = {row.media_key: row for row in rows}
    return [by_key[key] for key in keys if key in by_key]


def home_sections(db: Session, user: User | None) -> dict[str, Any]:
    live_sections = _refresh_home_from_tmdb(db)
    tmdb_count = int(
        db.scalar(select(func.count(Media.id)).where(Media.provider == "tmdb")) or 0
    )
    if tmdb_count == 0:
        # No fake/demo catalog is used in the final build. A missing TMDB
        # credential or an upstream outage must be visible instead of silently
        # pretending that a tiny hard-coded catalog is production data.
        try:
            seed_provider_catalog(db)
        except (MediaProviderUnavailableError, MediaProviderConfigurationError) as exc:
            raise AppError(
                503,
                "provider_unavailable",
                "سرویس اطلاعات فیلم و سریال در دسترس نیست.",
                detail="TMDB is not configured/reachable and no cached TMDB catalog exists.",
            ) from exc

    if live_sections:
        popular_movies = _media_in_key_order(db, live_sections.get("popular_movies"))[:12]
        popular_series = _media_in_key_order(db, live_sections.get("popular_series"))[:12]
        new_releases = _media_in_key_order(db, live_sections.get("new_releases"))[:12]
        top_rated = _media_in_key_order(db, live_sections.get("top_rated"))[:12]
        provider_recommendations = _media_in_key_order(
            db, live_sections.get("recommendations")
        )[:12]
    else:
        # Stale PostgreSQL fallback when TMDB/Redis is unavailable.
        popular_movies = _top_media(
            db, "movie", Media.provider_vote_count.desc().nullslast()
        )
        popular_series = _top_media(
            db, "series", Media.provider_vote_count.desc().nullslast()
        )
        new_releases = _top_media(db, None, Media.release_year.desc().nullslast())
        top_rated = _top_media(db, None, Media.provider_rating.desc().nullslast())
        provider_recommendations = recommendations_for(db, None)

    recommended = recommendations_for(db, user) if user else provider_recommendations
    return {
        "popular_movies": media_summaries(db, popular_movies),
        "popular_series": media_summaries(db, popular_series),
        "new_releases": media_summaries(db, new_releases),
        "top_rated": media_summaries(db, top_rated),
        "recommendations": media_summaries(db, recommended),
    }

