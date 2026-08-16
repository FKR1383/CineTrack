from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = "CineTrack Advanced API"
    environment: str = "development"
    debug: bool = False
    api_v1_prefix: str = "/api/v1"
    public_base_url: str = "https://31.57.118.82"
    cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=lambda: ["*"])

    database_url: str = "sqlite:///./cinetrack.db"
    redis_url: str | None = None
    media_cache_ttl_seconds: int = 86_400
    search_cache_ttl_seconds: int = 3_600
    home_cache_ttl_seconds: int = 1_800

    jwt_secret: SecretStr = SecretStr("change-this-in-production-with-at-least-32-characters")
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    short_refresh_token_days: int = 30
    password_reset_minutes: int = 30

    upload_dir: Path = Path("uploads")
    max_upload_bytes: int = 5 * 1024 * 1024
    allowed_image_types: Annotated[list[str], NoDecode] = Field(
        default_factory=lambda: ["image/jpeg", "image/png", "image/webp"]
    )

    mail_mode: str = "console"  # console | smtp
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: SecretStr | None = None
    smtp_from: str = "no-reply@cinetrack.local"
    smtp_starttls: bool = True

    # External movie/series metadata provider. Production uses TMDB only.
    media_provider: str = "tmdb"
    tmdb_api_base_url: str = "https://api.themoviedb.org/3"
    tmdb_image_base_url: str = "https://image.tmdb.org/t/p"
    tmdb_read_access_token: SecretStr | None = None
    tmdb_api_key: SecretStr | None = None
    tmdb_language: str = "en-US"
    tmdb_region: str = "US"
    tmdb_include_adult: bool = False
    tmdb_request_timeout_seconds: int = 15
    tmdb_search_live: bool = True

    # Server-side poster proxy/cache. Flutter never talks to TMDB's image CDN directly.
    poster_download_timeout_seconds: int = 15
    poster_max_source_bytes: int = 12 * 1024 * 1024
    poster_webp_quality: int = Field(default=80, ge=50, le=95)
    poster_max_width: int = Field(default=600, ge=200, le=1600)

    admin_email: str = "admin@cinetrack.example"
    admin_username: str = "admin"
    admin_password: SecretStr = SecretStr("Admin123!ChangeMe")

    rate_limit_per_minute: int = 120
    trust_proxy_headers: bool = True

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("allowed_image_types", mode="before")
    @classmethod
    def parse_allowed_image_types(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("jwt_secret")
    @classmethod
    def validate_jwt_secret(cls, value: SecretStr) -> SecretStr:
        if len(value.get_secret_value()) < 32:
            raise ValueError("JWT_SECRET must be at least 32 characters")
        return value

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @property
    def tmdb_configured(self) -> bool:
        token = self.tmdb_read_access_token
        api_key = self.tmdb_api_key
        return bool(
            (token and token.get_secret_value().strip())
            or (api_key and api_key.get_secret_value().strip())
        )


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    return settings
