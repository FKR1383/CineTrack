from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import CustomList, CustomListItem, Media, User
from app.schemas.lists import CustomListCreateRequest, CustomListUpdateRequest
from app.services.media import ensure_media, media_summaries


def _owned_list(db: Session, user: User, list_id: str) -> CustomList:
    item = db.get(CustomList, list_id)
    if item is None:
        raise AppError(404, "list_not_found", "فهرست شخصی پیدا نشد.")
    if item.user_id != user.id and user.role != "admin":
        raise AppError(403, "not_list_owner", "اجازه دسترسی به این فهرست را ندارید.")
    return item


def create_list(db: Session, user: User, data: CustomListCreateRequest) -> CustomList:
    duplicate = db.scalar(
        select(CustomList).where(
            CustomList.user_id == user.id, func.lower(CustomList.name) == data.name.strip().casefold()
        )
    )
    if duplicate:
        raise AppError(409, "duplicate_list_name", "فهرستی با این نام وجود دارد.")
    item = CustomList(
        user_id=user.id,
        name=data.name.strip(),
        description=data.description.strip() if data.description else None,
        is_public=data.is_public,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def update_list(
    db: Session, user: User, list_id: str, data: CustomListUpdateRequest
) -> CustomList:
    item = _owned_list(db, user, list_id)
    updates = data.model_dump(exclude_unset=True)
    if "name" in updates and updates["name"]:
        name = updates["name"].strip()
        duplicate = db.scalar(
            select(CustomList).where(
                CustomList.user_id == user.id,
                func.lower(CustomList.name) == name.casefold(),
                CustomList.id != item.id,
            )
        )
        if duplicate:
            raise AppError(409, "duplicate_list_name", "فهرستی با این نام وجود دارد.")
        updates["name"] = name
    for field, value in updates.items():
        if isinstance(value, str):
            value = value.strip() or None
        setattr(item, field, value)
    db.commit()
    db.refresh(item)
    return item


def delete_list(db: Session, user: User, list_id: str) -> None:
    item = _owned_list(db, user, list_id)
    db.delete(item)
    db.commit()


def add_item(db: Session, user: User, list_id: str, media_id: str) -> None:
    custom_list = _owned_list(db, user, list_id)
    media = ensure_media(db, media_id)
    duplicate = db.scalar(
        select(CustomListItem).where(
            CustomListItem.list_id == custom_list.id, CustomListItem.media_id == media.id
        )
    )
    if duplicate:
        return
    max_position = db.scalar(
        select(func.max(CustomListItem.position)).where(CustomListItem.list_id == custom_list.id)
    )
    db.add(
        CustomListItem(
            list_id=custom_list.id,
            media_id=media.id,
            position=int(max_position or 0) + 1,
        )
    )
    db.commit()


def remove_item(db: Session, user: User, list_id: str, media_id: str) -> None:
    custom_list = _owned_list(db, user, list_id)
    media = db.scalar(select(Media).where(Media.media_key == media_id))
    if media is None:
        return
    item = db.scalar(
        select(CustomListItem).where(
            CustomListItem.list_id == custom_list.id, CustomListItem.media_id == media.id
        )
    )
    if item:
        db.delete(item)
        db.commit()


def list_summaries(db: Session, user: User) -> list[dict]:
    lists = db.scalars(
        select(CustomList).where(CustomList.user_id == user.id).order_by(CustomList.updated_at.desc())
    ).all()
    return [
        {
            "id": item.id,
            "name": item.name,
            "description": item.description,
            "is_public": item.is_public,
            "item_count": len(item.items),
            "created_at": item.created_at,
            "updated_at": item.updated_at,
        }
        for item in lists
    ]


def list_detail(db: Session, user: User, list_id: str) -> dict:
    item = _owned_list(db, user, list_id)
    sorted_items = sorted(item.items, key=lambda value: (value.position, value.added_at))
    media = [value.media for value in sorted_items]
    return {
        "id": item.id,
        "name": item.name,
        "description": item.description,
        "is_public": item.is_public,
        "item_count": len(media),
        "created_at": item.created_at,
        "updated_at": item.updated_at,
        "items": media_summaries(db, media),
    }
