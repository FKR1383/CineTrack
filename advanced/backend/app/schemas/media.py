from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator


class MediaSummary(BaseModel):
    media_id: str
    provider: str = "tmdb"
    tmdb_id: int | None = None
    imdb_id: str | None = None
    media_type: str
    title: str
    original_title: str | None = None
    poster_url: str | None = None
    plot: str | None = None
    genres: list[str] = Field(default_factory=list)
    release_year: int | None = None
    end_year: int | None = None
    provider_rating: float | None = None
    app_rating: float | None = None
    rating_count: int = 0
    release_status: str | None = None
    season_count: int | None = None
    episode_count: int | None = None


class RatingDistribution(BaseModel):
    total: int
    percentages: dict[int, float]
    counts: dict[int, int]


class UserMediaState(BaseModel):
    watch_status: str | None = None
    is_favorite: bool = False
    user_rating: int | None = None
    watched_episodes: int = 0
    remaining_episodes: int = 0
    progress_percent: float = 0
    progress_color: str = "black"
    progress_hex: str = "#212121"


class MediaDetail(MediaSummary):
    release_date: date | None = None
    runtime_minutes: int | None = None
    countries: list[str] = Field(default_factory=list)
    directors: list[str] = Field(default_factory=list)
    cast: list[str] = Field(default_factory=list)
    provider_vote_count: int | None = None
    rating_distribution: RatingDistribution
    user_state: UserMediaState | None = None
    cached_at: datetime | None = None


class EpisodeResponse(BaseModel):
    episode_id: str
    provider: str = "tmdb"
    tmdb_id: int | None = None
    imdb_id: str | None = None
    season_number: int
    episode_number: int
    title: str
    release_date: date | None
    runtime_minutes: int | None
    plot: str | None
    watched: bool = False


class SeasonResponse(BaseModel):
    season_number: int
    title: str | None
    episode_count: int
    episodes: list[EpisodeResponse] = Field(default_factory=list)


class SearchFilters(BaseModel):
    q: str | None = None
    media_type: str | None = None
    actor: str | None = None
    director: str | None = None
    genre: str | None = None
    year: int | None = Field(default=None, ge=1870, le=2200)


class HomeSectionsResponse(BaseModel):
    popular_movies: list[MediaSummary]
    popular_series: list[MediaSummary]
    new_releases: list[MediaSummary]
    top_rated: list[MediaSummary]
    recommendations: list[MediaSummary]


class WatchStatusRequest(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def valid_status(cls, value: str) -> str:
        allowed = {"plan_to_watch", "watching", "completed", "paused", "dropped", "favorite"}
        if value not in allowed:
            raise ValueError(f"status must be one of {sorted(allowed)}")
        return value


class EpisodeWatchRequest(BaseModel):
    watched: bool = True


class RatingRequest(BaseModel):
    score: int = Field(ge=1, le=5)


class CommentCreateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    is_spoiler: bool = False

    @field_validator("text")
    @classmethod
    def strip_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Comment text cannot be empty")
        return value


class CommentUpdateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    is_spoiler: bool = False

    @field_validator("text")
    @classmethod
    def strip_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Comment text cannot be empty")
        return value


class CommentResponse(BaseModel):
    id: str
    text: str
    username: str
    user_avatar_url: str | None
    created_at: datetime
    updated_at: datetime
    is_spoiler: bool
    is_hidden: bool
    own_comment: bool = False


class ProgressResponse(BaseModel):
    media_id: str
    watched_episodes: int
    total_episodes: int
    remaining_episodes: int
    progress_percent: float
    progress_color: str
    progress_hex: str
    release_status: str | None


class LibraryEntry(BaseModel):
    media: MediaSummary
    watch_status: str | None
    is_favorite: bool
    progress: ProgressResponse | None
    updated_at: datetime
