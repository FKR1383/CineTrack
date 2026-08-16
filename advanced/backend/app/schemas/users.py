from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator


class ProfileUpdateRequest(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=80)
    last_name: str | None = Field(default=None, min_length=1, max_length=80)
    username: str | None = Field(
        default=None, min_length=3, max_length=40, pattern=r"^[A-Za-z0-9_.-]+$"
    )
    email: EmailStr | None = None
    bio: str | None = Field(default=None, max_length=500)

    @field_validator("first_name", "last_name", "username", mode="before")
    @classmethod
    def strip_profile_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("bio", mode="before")
    @classmethod
    def normalize_bio(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None


class UserStatsResponse(BaseModel):
    watched_movies: int
    watched_series: int
    watched_episodes: int
    approximate_watch_minutes: int
    approximate_watch_hours: float
    favorite_genre: str | None
    average_user_rating: float | None
    favorites_count: int
    custom_lists_count: int


class ActivityItem(BaseModel):
    kind: str
    media_id: str
    media_title: str
    media_type: str
    occurred_at: datetime
    detail: str | None = None


class ActivityResponse(BaseModel):
    items: list[ActivityItem]
    total: int
