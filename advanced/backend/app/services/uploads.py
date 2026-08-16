from __future__ import annotations

import io
import uuid
from pathlib import Path

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError

from app.config import get_settings
from app.core.errors import AppError

settings = get_settings()


async def save_profile_image(upload: UploadFile) -> str:
    if upload.content_type not in settings.allowed_image_types:
        raise AppError(
            422,
            "invalid_image_type",
            "فرمت تصویر پروفایل مجاز نیست.",
            detail=f"Allowed types: {', '.join(settings.allowed_image_types)}",
        )
    content = await upload.read(settings.max_upload_bytes + 1)
    if len(content) > settings.max_upload_bytes:
        raise AppError(413, "image_too_large", "حجم تصویر پروفایل بیش از حد مجاز است.")
    try:
        image = Image.open(io.BytesIO(content))
        image.verify()
        image = Image.open(io.BytesIO(content)).convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise AppError(422, "invalid_image", "فایل ارسال‌شده تصویر معتبر نیست.") from exc
    image.thumbnail((512, 512))
    avatars = settings.upload_dir / "avatars"
    avatars.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid.uuid4()}.webp"
    destination = avatars / filename
    image.save(destination, "WEBP", quality=85, method=6)
    return f"/uploads/avatars/{filename}"


def remove_upload(relative_url: str | None) -> None:
    if not relative_url or not relative_url.startswith("/uploads/"):
        return
    relative = relative_url.removeprefix("/uploads/")
    path = (settings.upload_dir / relative).resolve()
    root = settings.upload_dir.resolve()
    if root in path.parents and path.exists() and path.is_file():
        path.unlink(missing_ok=True)
