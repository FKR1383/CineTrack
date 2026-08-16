from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


class MediaProviderError(RuntimeError):
    pass


class MediaNotFoundError(MediaProviderError):
    pass


class MediaProviderUnavailableError(MediaProviderError):
    pass


class MediaProviderConfigurationError(MediaProviderUnavailableError):
    pass


@dataclass(slots=True)
class ProviderSearchPage:
    items: list[dict[str, Any]]
    page: int
    page_size: int
    total: int
    total_pages: int


class MediaProvider(ABC):
    name: str

    @abstractmethod
    def search(
        self,
        *,
        query: str | None,
        media_type: str | None,
        actor: str | None,
        director: str | None,
        genre: str | None,
        year: int | None,
        page: int,
        page_size: int,
    ) -> ProviderSearchPage:
        raise NotImplementedError

    @abstractmethod
    def get_title(self, media_key: str) -> dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def get_episodes(self, media_key: str) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def home_sections(self) -> dict[str, list[dict[str, Any]]]:
        raise NotImplementedError
