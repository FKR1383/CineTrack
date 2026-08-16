from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class AdminUserUpdateRequest(BaseModel):
    role: str | None = Field(default=None, pattern=r"^(user|admin)$")
    is_active: bool | None = None


class ReportCreateRequest(BaseModel):
    reason: str = Field(min_length=3, max_length=500)

    @field_validator("reason")
    @classmethod
    def normalize_reason(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 3:
            raise ValueError("Report reason must contain at least 3 characters")
        return value


class ReportResolveRequest(BaseModel):
    status: str = Field(pattern=r"^(open|reviewed|resolved|dismissed)$")
    resolution_note: str | None = Field(default=None, max_length=500)

    @field_validator("resolution_note", mode="before")
    @classmethod
    def normalize_resolution_note(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        normalized = value.strip()
        return normalized or None


class AdminReportResponse(BaseModel):
    id: str
    reporter_username: str
    comment_id: str | None
    reason: str
    status: str
    resolution_note: str | None
    created_at: datetime
    updated_at: datetime


class AdminStatsResponse(BaseModel):
    users_total: int
    users_active: int
    media_total: int
    movies_total: int
    series_total: int
    comments_total: int
    open_reports: int
    ratings_total: int
    favorites_total: int
    watched_entries_total: int


class AdminMediaUpdateRequest(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    original_title: str | None = Field(default=None, max_length=500)
    plot: str | None = Field(default=None, max_length=10000)
    poster_url: str | None = Field(default=None, max_length=1000)
    genres: list[str] | None = None
    release_status: str | None = Field(default=None, max_length=40)
