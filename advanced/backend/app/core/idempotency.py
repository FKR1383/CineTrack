from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, delete, select
from sqlalchemy.orm import Session

from app.models import IdempotencyRecord, User


def get_saved_response(
    db: Session, *, user: User, key: str | None, method: str, path: str
) -> tuple[int, dict[str, Any]] | None:
    if not key:
        return None
    now = datetime.now(timezone.utc)
    db.execute(delete(IdempotencyRecord).where(IdempotencyRecord.expires_at < now))
    record = db.scalar(
        select(IdempotencyRecord).where(
            and_(
                IdempotencyRecord.user_id == user.id,
                IdempotencyRecord.key == key,
                IdempotencyRecord.method == method,
                IdempotencyRecord.path == path,
            )
        )
    )
    if record:
        return record.response_status, record.response_body
    return None


def save_response(
    db: Session,
    *,
    user: User,
    key: str | None,
    method: str,
    path: str,
    status: int,
    body: dict[str, Any],
) -> None:
    if not key:
        return
    db.add(
        IdempotencyRecord(
            user_id=user.id,
            key=key,
            method=method,
            path=path,
            response_status=status,
            response_body=body,
            expires_at=datetime.now(timezone.utc) + timedelta(hours=24),
        )
    )
