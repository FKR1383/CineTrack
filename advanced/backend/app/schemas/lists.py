from __future__ import annotations

from datetime import datetime

from pydantic import AliasChoices, BaseModel, Field, field_validator

from app.schemas.media import MediaSummary


class _CustomListTextMixin(BaseModel):
    @field_validator("name", mode="before", check_fields=False)
    @classmethod
    def normalize_name(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("description", mode="before", check_fields=False)
    @classmethod
    def normalize_description(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        normalized = value.strip()
        return normalized or None


class CustomListCreateRequest(_CustomListTextMixin):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    is_public: bool = False


class CustomListUpdateRequest(_CustomListTextMixin):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    is_public: bool | None = None


class ListItemAddRequest(BaseModel):
    # validation_alias keeps older APKs compatible during migration.
    media_id: str = Field(
        min_length=3,
        max_length=64,
        validation_alias=AliasChoices("media_id", "imdb_id"),
    )


class CustomListSummary(BaseModel):
    id: str
    name: str
    description: str | None
    is_public: bool
    item_count: int
    created_at: datetime
    updated_at: datetime


class CustomListDetail(CustomListSummary):
    items: list[MediaSummary]
