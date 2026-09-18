"""Application settings.

Everything is read from the environment once, at import, and validated
immediately. A production deploy with a missing secret fails at boot with a
clear message instead of at 2am on the first request that needs it.
"""

from functools import lru_cache
from typing import Annotated, Literal

from pydantic import Field, computed_field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

INSECURE_SECRET = "dev-insecure-change-me"


# pydantic-settings JSON-decodes complex fields in the source layer, before
# any field validator runs, so ALLOWED_ORIGINS="http://a,http://b" fails with
# an opaque parse error. NoDecode hands us the raw string to split ourselves —
# commas are what people actually type into a Railway variable box.
CsvList = Annotated[list[str], NoDecode]


def _split_csv(value):
    """Accept `a,b,c` as well as a JSON list."""
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return []
        if value.startswith("["):
            return value
        return [item.strip() for item in value.split(",") if item.strip()]
    return value


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    ENVIRONMENT: Literal["development", "test", "production"] = "development"
    APP_NAME: str = "app"
    VERSION: str = "0.1.0"

    SECRET_KEY: str = INSECURE_SECRET
    DATABASE_URL: str = (
        "postgresql+asyncpg://postgres:postgres@localhost:5432/app"
    )
    PUBLIC_BASE_URL: str = "http://localhost:8000"

    ALLOWED_ORIGINS: CsvList = Field(default_factory=list)
    ALLOWED_HOSTS: CsvList = Field(default_factory=lambda: ["*"])

    RESEND_API_KEY: str | None = None
    EMAIL_FROM: str = "onboarding@resend.dev"

    SESSION_COOKIE_NAME: str = "session"
    SESSION_LIFETIME_SECONDS: int = 60 * 60 * 24 * 14  # 14 days
    RESET_TOKEN_LIFETIME_SECONDS: int = 60 * 60  # 1 hour

    RATE_LIMIT_LOGIN: str = "10/minute"
    RATE_LIMIT_FORGOT_PASSWORD: str = "5/hour"
    RATE_LIMIT_REGISTER: str = "10/hour"

    # Extra CSP sources a project needs on top of the strict 'self' baseline.
    CSP_ALLOW_INLINE_STYLES: bool = False
    CSP_STYLE_SRC_EXTRA: CsvList = Field(default_factory=list)
    CSP_FONT_SRC_EXTRA: CsvList = Field(default_factory=list)
    CSP_IMG_SRC_EXTRA: CsvList = Field(default_factory=list)
    CSP_CONNECT_SRC_EXTRA: CsvList = Field(default_factory=list)

    _csv_fields = field_validator(
        "ALLOWED_ORIGINS",
        "ALLOWED_HOSTS",
        "CSP_STYLE_SRC_EXTRA",
        "CSP_FONT_SRC_EXTRA",
        "CSP_IMG_SRC_EXTRA",
        "CSP_CONNECT_SRC_EXTRA",
        mode="before",
    )(_split_csv)

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def _coerce_async_driver(cls, value: str) -> str:
        """Railway hands out `postgresql://`; async SQLAlchemy needs asyncpg.

        Getting this wrong produces `InvalidRequestError: The asyncio extension
        requires an async driver`, which reads like a code bug rather than a
        URL scheme problem. Fix it here, once.
        """
        if isinstance(value, str):
            for prefix in ("postgresql://", "postgres://"):
                if value.startswith(prefix):
                    return "postgresql+asyncpg://" + value[len(prefix):]
        return value

    @computed_field
    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @computed_field
    @property
    def sync_database_url(self) -> str:
        """Alembic runs migrations synchronously."""
        return self.DATABASE_URL.replace("+asyncpg", "")

    @computed_field
    @property
    def cookie_secure(self) -> bool:
        return self.is_production

    @model_validator(mode="after")
    def _production_requires_real_config(self) -> "Settings":
        if not self.is_production:
            return self

        problems: list[str] = []
        if self.SECRET_KEY == INSECURE_SECRET or len(self.SECRET_KEY) < 32:
            problems.append(
                "SECRET_KEY must be set to a random value of at least 32 "
                "characters (try: python -c 'import secrets; "
                "print(secrets.token_urlsafe(48))')"
            )
        if not self.RESEND_API_KEY:
            problems.append(
                "RESEND_API_KEY is required: password reset cannot send mail "
                "without it"
            )
        if self.ALLOWED_HOSTS == ["*"]:
            problems.append(
                "ALLOWED_HOSTS must name your real host(s), not '*'"
            )
        if self.PUBLIC_BASE_URL.startswith("http://"):
            problems.append(
                "PUBLIC_BASE_URL must be https:// in production — reset links "
                "are built from it"
            )

        if problems:
            raise ValueError(
                "Refusing to start in production:\n  - "
                + "\n  - ".join(problems)
            )
        return self

    def content_security_policy(self) -> str:
        style = ["'self'", *self.CSP_STYLE_SRC_EXTRA]
        if self.CSP_ALLOW_INLINE_STYLES:
            style.append("'unsafe-inline'")

        directives = {
            "default-src": ["'self'"],
            "script-src": ["'self'"],
            "style-src": style,
            "font-src": ["'self'", *self.CSP_FONT_SRC_EXTRA],
            "img-src": ["'self'", "data:", *self.CSP_IMG_SRC_EXTRA],
            "connect-src": ["'self'", *self.CSP_CONNECT_SRC_EXTRA],
            "frame-ancestors": ["'none'"],
            "base-uri": ["'self'"],
            "form-action": ["'self'"],
            "object-src": ["'none'"],
        }
        return "; ".join(f"{k} {' '.join(v)}" for k, v in directives.items())


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
