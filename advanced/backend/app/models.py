from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def uuid_str() -> str:
    return str(uuid.uuid4())


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    first_name: Mapped[str] = mapped_column(String(80))
    last_name: Mapped[str] = mapped_column(String(80))
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    bio: Mapped[str | None] = mapped_column(String(500), nullable=True)
    role: Mapped[str] = mapped_column(String(20), default="user", index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)

    refresh_tokens: Mapped[list[RefreshToken]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    jti: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    device_info: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped[User] = relationship(back_populates="refresh_tokens")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Media(Base, TimestampMixin):
    __tablename__ = "media"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    # Historical database column name is kept for zero-data-loss migration from
    # the original IMDb build.  Application code treats it as a generic media key.
    media_key: Mapped[str] = mapped_column("imdb_id", String(64), unique=True, index=True)
    provider: Mapped[str] = mapped_column(String(20), default="tmdb", index=True)
    provider_id: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)
    tmdb_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    external_imdb_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)
    media_type: Mapped[str] = mapped_column(String(20), index=True)  # movie | series
    title: Mapped[str] = mapped_column(String(500), index=True)
    original_title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # Original upstream poster URL; never returned directly to Flutter.
    poster_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    plot: Mapped[str | None] = mapped_column(Text, nullable=True)
    genres: Mapped[list[str]] = mapped_column(JSON, default=list)
    release_year: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    end_year: Mapped[int | None] = mapped_column(Integer, nullable=True)
    release_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    runtime_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    countries: Mapped[list[str]] = mapped_column(JSON, default=list)
    directors: Mapped[list[str]] = mapped_column(JSON, default=list)
    cast: Mapped[list[str]] = mapped_column(JSON, default=list)
    # Historical DB column names are preserved; values now represent the active
    # provider (TMDB) rating/vote count.
    provider_rating: Mapped[float | None] = mapped_column("imdb_rating", Float, nullable=True, index=True)
    provider_vote_count: Mapped[int | None] = mapped_column("imdb_vote_count", Integer, nullable=True)
    release_status: Mapped[str | None] = mapped_column(String(40), nullable=True)
    season_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    episode_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    raw_payload: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    cached_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)

    seasons: Mapped[list[Season]] = relationship(
        back_populates="media", cascade="all, delete-orphan", order_by="Season.number"
    )

    __table_args__ = (
        CheckConstraint("media_type IN ('movie','series')", name="ck_media_type"),
        UniqueConstraint("provider", "media_type", "provider_id", name="uq_media_provider_type_id"),
        Index("ix_media_title_year", "title", "release_year"),
    )


class Season(Base, TimestampMixin):
    __tablename__ = "seasons"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    number: Mapped[int] = mapped_column(Integer)
    title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    episode_count: Mapped[int] = mapped_column(Integer, default=0)

    media: Mapped[Media] = relationship(back_populates="seasons")
    episodes: Mapped[list[Episode]] = relationship(
        back_populates="season", cascade="all, delete-orphan", order_by="Episode.number"
    )

    __table_args__ = (UniqueConstraint("media_id", "number", name="uq_season_media_number"),)


class Episode(Base, TimestampMixin):
    __tablename__ = "episodes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    season_id: Mapped[str] = mapped_column(ForeignKey("seasons.id", ondelete="CASCADE"), index=True)
    episode_key: Mapped[str] = mapped_column("imdb_id", String(64), unique=True, index=True)
    provider: Mapped[str] = mapped_column(String(20), default="tmdb", index=True)
    provider_id: Mapped[str | None] = mapped_column(String(40), nullable=True, index=True)
    tmdb_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    external_imdb_id: Mapped[str | None] = mapped_column(String(20), nullable=True, index=True)
    number: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(String(500))
    release_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    runtime_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    plot: Mapped[str | None] = mapped_column(Text, nullable=True)

    season: Mapped[Season] = relationship(back_populates="episodes")

    __table_args__ = (UniqueConstraint("season_id", "number", name="uq_episode_season_number"),)


class UserMedia(Base, TimestampMixin):
    __tablename__ = "user_media"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    watch_status: Mapped[str | None] = mapped_column(String(30), nullable=True, index=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    media: Mapped[Media] = relationship()

    __table_args__ = (
        UniqueConstraint("user_id", "media_id", name="uq_user_media"),
        CheckConstraint(
            "watch_status IS NULL OR watch_status IN "
            "('plan_to_watch','watching','completed','paused','dropped')",
            name="ck_watch_status",
        ),
    )


class UserEpisode(Base, TimestampMixin):
    __tablename__ = "user_episodes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    episode_id: Mapped[str] = mapped_column(ForeignKey("episodes.id", ondelete="CASCADE"), index=True)
    watched: Mapped[bool] = mapped_column(Boolean, default=True)
    watched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=utcnow)

    episode: Mapped[Episode] = relationship()

    __table_args__ = (UniqueConstraint("user_id", "episode_id", name="uq_user_episode"),)


class Rating(Base, TimestampMixin):
    __tablename__ = "ratings"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    score: Mapped[int] = mapped_column(Integer)

    __table_args__ = (
        UniqueConstraint("user_id", "media_id", name="uq_user_rating"),
        CheckConstraint("score >= 1 AND score <= 5", name="ck_rating_score"),
    )


class Comment(Base, TimestampMixin):
    __tablename__ = "comments"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    text: Mapped[str] = mapped_column(Text)
    is_spoiler: Mapped[bool] = mapped_column(Boolean, default=False)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    moderation_note: Mapped[str | None] = mapped_column(String(500), nullable=True)

    user: Mapped[User] = relationship()


class Favorite(Base):
    __tablename__ = "favorites"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    media: Mapped[Media] = relationship()

    __table_args__ = (UniqueConstraint("user_id", "media_id", name="uq_user_favorite"),)


class CustomList(Base, TimestampMixin):
    __tablename__ = "custom_lists"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=False)

    items: Mapped[list[CustomListItem]] = relationship(
        back_populates="custom_list", cascade="all, delete-orphan"
    )

    __table_args__ = (UniqueConstraint("user_id", "name", name="uq_user_list_name"),)


class CustomListItem(Base):
    __tablename__ = "custom_list_items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    list_id: Mapped[str] = mapped_column(ForeignKey("custom_lists.id", ondelete="CASCADE"), index=True)
    media_id: Mapped[str] = mapped_column(ForeignKey("media.id", ondelete="CASCADE"), index=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    custom_list: Mapped[CustomList] = relationship(back_populates="items")
    media: Mapped[Media] = relationship()

    __table_args__ = (UniqueConstraint("list_id", "media_id", name="uq_list_media"),)


class Report(Base, TimestampMixin):
    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    reporter_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    comment_id: Mapped[str | None] = mapped_column(
        ForeignKey("comments.id", ondelete="CASCADE"), nullable=True, index=True
    )
    reason: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(20), default="open", index=True)
    resolution_note: Mapped[str | None] = mapped_column(String(500), nullable=True)

    reporter: Mapped[User] = relationship(foreign_keys=[reporter_id])
    comment: Mapped[Comment | None] = relationship()


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    key: Mapped[str] = mapped_column(String(100))
    method: Mapped[str] = mapped_column(String(10))
    path: Mapped[str] = mapped_column(String(500))
    response_status: Mapped[int] = mapped_column(Integer)
    response_body: Mapped[dict[str, Any]] = mapped_column(JSON)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", "key", "method", "path", name="uq_idempotency_scope"),
    )


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_str)
    actor_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(100), index=True)
    target_type: Mapped[str | None] = mapped_column(String(80), nullable=True)
    target_id: Mapped[str | None] = mapped_column(String(80), nullable=True)
    details: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
