"""Email bodies.

Plain, inline-styled HTML: every client renders it, nothing to build.
"""

from urllib.parse import quote

from app.config import settings

STYLE_BODY = (
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
    "line-height:1.5;color:#1a1a1a;max-width:480px;margin:0 auto;padding:24px"
)
STYLE_BUTTON = (
    "display:inline-block;padding:12px 24px;background:#0A0E1A;color:#fff;"
    "text-decoration:none;border-radius:8px;font-weight:600;margin:20px 0"
)


def reset_password_url(token: str) -> str:
    return f"{settings.PUBLIC_BASE_URL.rstrip('/')}/?reset_token={quote(token)}"


def reset_password_email(token: str) -> tuple[str, str]:
    """Return (subject, html) for a password reset."""
    url = reset_password_url(token)
    minutes = settings.RESET_TOKEN_LIFETIME_SECONDS // 60
    html = f"""
    <div style="{STYLE_BODY}">
      <h2 style="margin:0 0 12px">Reset your password</h2>
      <p>We received a request to reset your {settings.APP_NAME} password.
         This link expires in {minutes} minutes and can only be used once.</p>
      <p><a href="{url}" style="{STYLE_BUTTON}">Choose a new password</a></p>
      <p style="font-size:13px;color:#666">
        If the button doesn't work, paste this into your browser:<br>
        <span style="word-break:break-all">{url}</span>
      </p>
      <p style="font-size:13px;color:#666">
        Didn't ask for this? You can ignore this email — your password stays
        as it is.
      </p>
    </div>
    """
    return f"Reset your {settings.APP_NAME} password", html
