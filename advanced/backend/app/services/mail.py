from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


def send_password_reset(email: str, token: str) -> None:
    reset_link = f"timetv://reset-password?token={token}"
    subject = "بازیابی رمز عبور CineTrack"
    body = (
        "برای تغییر رمز عبور، پیوند زیر را در اپلیکیشن باز کنید:\n\n"
        f"{reset_link}\n\n"
        "این پیوند مدت محدودی معتبر است. اگر شما این درخواست را نداده‌اید، آن را نادیده بگیرید."
    )
    if settings.mail_mode == "console":
        logger.warning("Password reset token for %s: %s", email, token)
        return
    if not settings.smtp_host:
        raise RuntimeError("SMTP_HOST is required when MAIL_MODE=smtp")
    message = EmailMessage()
    message["From"] = settings.smtp_from
    message["To"] = email
    message["Subject"] = subject
    message.set_content(body)
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
        if settings.smtp_starttls:
            smtp.starttls()
        if settings.smtp_username and settings.smtp_password:
            smtp.login(settings.smtp_username, settings.smtp_password.get_secret_value())
        smtp.send_message(message)
