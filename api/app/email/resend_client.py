"""Transactional email via Resend.

Resend only delivers to arbitrary inboxes from a domain you have verified. The
default `onboarding@resend.dev` sender delivers ONLY to the email address that
owns the Resend account — fine for your own testing, useless for real users.
Verify a domain and set EMAIL_FROM before asking anyone else to reset a
password.
"""

import asyncio
import logging

import resend

from app.config import settings

logger = logging.getLogger("app.email")


class EmailNotConfigured(RuntimeError):
    pass


async def send_email(to: str, subject: str, html: str) -> None:
    """Send one email.

    The resend SDK is synchronous, so it runs in a worker thread to avoid
    blocking the event loop.
    """
    if not settings.RESEND_API_KEY:
        raise EmailNotConfigured(
            "RESEND_API_KEY is not set, so no mail can be sent. Set it in "
            "your environment (see .env.example)."
        )

    resend.api_key = settings.RESEND_API_KEY
    params: resend.Emails.SendParams = {
        "from": settings.EMAIL_FROM,
        "to": [to],
        "subject": subject,
        "html": html,
    }

    def _send() -> None:
        resend.Emails.send(params)

    await asyncio.to_thread(_send)
    logger.info("Sent %r to %s", subject, to)
