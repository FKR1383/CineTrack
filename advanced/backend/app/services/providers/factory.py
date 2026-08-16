from __future__ import annotations

from functools import lru_cache

from app.config import get_settings
from app.services.providers.base import MediaProvider, MediaProviderConfigurationError
from app.services.providers.tmdb import TMDBProvider


@lru_cache
def get_media_provider() -> MediaProvider:
    settings = get_settings()
    provider = settings.media_provider.lower().strip()
    if provider == "tmdb":
        return TMDBProvider()
    raise MediaProviderConfigurationError(
        f"Unsupported MEDIA_PROVIDER={settings.media_provider!r}; this build supports 'tmdb'."
    )
