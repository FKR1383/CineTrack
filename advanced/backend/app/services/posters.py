from __future__ import annotations

import hashlib
import io
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image, UnidentifiedImageError

from app.config import get_settings
from app.core.errors import AppError
from app.models import Media

settings = get_settings()


def public_poster_url(media: Media) -> str | None:
    """Expose only a same-origin poster URL to the Flutter client.

    The original TMDB image URL is intentionally kept server-side in
    ``Media.poster_url``. This preserves the advanced architecture:
    Flutter -> CineTrack backend -> TMDB image CDN.
    """
    if not media.poster_url:
        return None
    return f"{settings.api_v1_prefix}/media/{media.media_key}/poster"


def _cache_dir() -> Path:
    path = settings.upload_dir / "posters"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _source_cache_key(source_url: str) -> str:
    return hashlib.sha256(source_url.encode("utf-8")).hexdigest()[:16]


def poster_cache_path(media: Media) -> Path:
    source = media.poster_url or "none"
    return _cache_dir() / f"{media.media_key}-{_source_cache_key(source)}.webp"


def _validate_source_url(url: str) -> None:
    parsed = urlparse(url)
    allowed = urlparse(settings.tmdb_image_base_url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not allowed.hostname
        or parsed.hostname.casefold() != allowed.hostname.casefold()
    ):
        raise AppError(
            502,
            "poster_source_invalid",
            "نشانی پوستر معتبر نیست.",
            detail="Poster proxy only accepts the configured TMDB image origin.",
        )


def _download_source(url: str) -> bytes:
    _validate_source_url(url)
    try:
        with httpx.Client(
            timeout=settings.poster_download_timeout_seconds,
            follow_redirects=True,
            headers={
                "User-Agent": "CineTrack-Advanced/2.0 (+server-side TMDB poster cache)",
                "Accept": "image/avif,image/webp,image/jpeg,image/png,*/*;q=0.8",
            },
        ) as client:
            with client.stream("GET", url) as response:
                response.raise_for_status()
                content_type = (response.headers.get("content-type") or "").lower()
                if content_type and not content_type.startswith("image/"):
                    raise AppError(
                        502,
                        "poster_source_not_image",
                        "دریافت پوستر با خطا مواجه شد.",
                        detail=f"Remote content type was {content_type!r}.",
                    )
                data = bytearray()
                for chunk in response.iter_bytes():
                    data.extend(chunk)
                    if len(data) > settings.poster_max_source_bytes:
                        raise AppError(
                            413,
                            "poster_source_too_large",
                            "حجم پوستر بیش از حد مجاز است.",
                        )
                if not data:
                    raise AppError(502, "poster_source_empty", "پوستر دریافتی خالی است.")
                return bytes(data)
    except AppError:
        raise
    except (httpx.HTTPError, OSError) as exc:
        raise AppError(
            502,
            "poster_download_failed",
            "دریافت پوستر با خطا مواجه شد.",
            detail=str(exc),
        ) from exc


def _convert_to_webp(source: bytes, destination: Path) -> None:
    try:
        with Image.open(io.BytesIO(source)) as image:
            image.load()
            if image.mode not in {"RGB", "RGBA"}:
                image = image.convert("RGB")
            if image.width > settings.poster_max_width:
                height = max(1, round(image.height * settings.poster_max_width / image.width))
                image = image.resize((settings.poster_max_width, height), Image.Resampling.LANCZOS)
            tmp = destination.with_suffix(".tmp")
            image.save(tmp, format="WEBP", quality=settings.poster_webp_quality, method=4)
            tmp.replace(destination)
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise AppError(
            502,
            "poster_decode_failed",
            "فایل پوستر معتبر نیست.",
            detail=str(exc),
        ) from exc


def ensure_cached_poster(media: Media) -> Path:
    """Return a locally cached optimized poster, fetching only on cache miss."""
    if not media.poster_url:
        raise AppError(404, "poster_not_found", "پوستر این اثر موجود نیست.")
    target = poster_cache_path(media)
    if target.is_file() and target.stat().st_size > 0:
        return target

    # If an older cached version exists and the new upstream fetch fails, serve
    # it as a stale-but-usable fallback instead of breaking the app.
    stale = sorted(_cache_dir().glob(f"{media.media_key}-*.webp"), reverse=True)
    try:
        source = _download_source(media.poster_url)
        _convert_to_webp(source, target)
        return target
    except AppError:
        for candidate in stale:
            if candidate.is_file() and candidate.stat().st_size > 0:
                return candidate
        raise



def clear_cached_poster(media: Media) -> int:
    """Delete only derived poster files for a media row; never delete user data."""
    removed = 0
    for candidate in _cache_dir().glob(f"{media.media_key}-*.webp"):
        try:
            candidate.unlink(missing_ok=True)
            removed += 1
        except OSError:
            pass
    return removed
