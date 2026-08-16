from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import Comment, Favorite, Media, Rating, Report, User, UserMedia


def system_stats(db: Session) -> dict:
    def count(model, *where) -> int:
        statement = select(func.count(model.id))
        if where:
            statement = statement.where(*where)
        return int(db.scalar(statement) or 0)

    return {
        "users_total": count(User),
        "users_active": count(User, User.is_active.is_(True)),
        "media_total": count(Media),
        "movies_total": count(Media, Media.media_type == "movie"),
        "series_total": count(Media, Media.media_type == "series"),
        "comments_total": count(Comment),
        "open_reports": count(Report, Report.status == "open"),
        "ratings_total": count(Rating),
        "favorites_total": count(Favorite),
        "watched_entries_total": count(UserMedia),
    }


def report_comment(db: Session, user: User, comment_id: str, reason: str) -> Report:
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise AppError(404, "comment_not_found", "نظر پیدا نشد.")
    existing = db.scalar(
        select(Report).where(
            Report.reporter_id == user.id,
            Report.comment_id == comment.id,
            Report.status == "open",
        )
    )
    if existing:
        return existing
    report = Report(reporter_id=user.id, comment_id=comment.id, reason=reason.strip())
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


def report_response(report: Report) -> dict:
    return {
        "id": report.id,
        "reporter_username": report.reporter.username,
        "comment_id": report.comment_id,
        "reason": report.reason,
        "status": report.status,
        "resolution_note": report.resolution_note,
        "created_at": report.created_at,
        "updated_at": report.updated_at,
    }
