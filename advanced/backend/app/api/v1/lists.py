from __future__ import annotations

from fastapi import APIRouter, status

from app.core.deps import CurrentUser, DB
from app.schemas.common import MessageResponse
from app.schemas.lists import (
    CustomListCreateRequest,
    CustomListDetail,
    CustomListSummary,
    CustomListUpdateRequest,
    ListItemAddRequest,
)
from app.services import lists as list_service

router = APIRouter(prefix="/me/lists", tags=["Custom lists"])


@router.get("", response_model=list[CustomListSummary])
def get_lists(db: DB, current_user: CurrentUser) -> list[dict]:
    return list_service.list_summaries(db, current_user)


@router.post("", response_model=CustomListSummary, status_code=status.HTTP_201_CREATED)
def create_list(
    data: CustomListCreateRequest, db: DB, current_user: CurrentUser
) -> dict:
    item = list_service.create_list(db, current_user, data)
    return {
        "id": item.id,
        "name": item.name,
        "description": item.description,
        "is_public": item.is_public,
        "item_count": 0,
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    }


@router.get("/{list_id}", response_model=CustomListDetail)
def get_list(list_id: str, db: DB, current_user: CurrentUser) -> dict:
    return list_service.list_detail(db, current_user, list_id)


@router.patch("/{list_id}", response_model=CustomListSummary)
def patch_list(
    list_id: str,
    data: CustomListUpdateRequest,
    db: DB,
    current_user: CurrentUser,
) -> dict:
    item = list_service.update_list(db, current_user, list_id, data)
    return {
        "id": item.id,
        "name": item.name,
        "description": item.description,
        "is_public": item.is_public,
        "item_count": len(item.items),
        "created_at": item.created_at,
        "updated_at": item.updated_at,
    }


@router.delete("/{list_id}", response_model=MessageResponse)
def remove_list(list_id: str, db: DB, current_user: CurrentUser) -> MessageResponse:
    list_service.delete_list(db, current_user, list_id)
    return MessageResponse(message="فهرست شخصی حذف شد.")


@router.post("/{list_id}/items", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
def add_list_item(
    list_id: str,
    data: ListItemAddRequest,
    db: DB,
    current_user: CurrentUser,
) -> MessageResponse:
    list_service.add_item(db, current_user, list_id, data.media_id)
    return MessageResponse(message="اثر به فهرست افزوده شد.")


@router.delete("/{list_id}/items/{media_id}", response_model=MessageResponse)
def remove_list_item(
    list_id: str, media_id: str, db: DB, current_user: CurrentUser
) -> MessageResponse:
    list_service.remove_item(db, current_user, list_id, media_id)
    return MessageResponse(message="اثر از فهرست حذف شد.")
