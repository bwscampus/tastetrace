from app.config import Settings
from app.main import create_app

PROD_ENV = {
    "ENVIRONMENT": "production",
    "SECRET_KEY": "x" * 48,
    "RESEND_API_KEY": "re_test_key",
    "ALLOWED_HOSTS": "app.example.com",
    "PUBLIC_BASE_URL": "https://app.example.com",
}


async def test_security_headers_present(client):
    response = await client.get("/api/health")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "frame-ancestors 'none'" in response.headers["Content-Security-Policy"]
    assert response.headers["X-Request-ID"]


async def test_docs_hidden_in_production():
    app = create_app(Settings(**PROD_ENV))
    assert app.docs_url is None
    assert app.openapi_url is None


async def test_docs_available_outside_production(client):
    assert (await client.get("/docs")).status_code == 200


def test_production_rejects_placeholder_secret():
    import pytest

    with pytest.raises(ValueError, match="SECRET_KEY"):
        Settings(**{**PROD_ENV, "SECRET_KEY": "dev-insecure-change-me"})


def test_production_requires_email_key():
    import pytest

    with pytest.raises(ValueError, match="RESEND_API_KEY"):
        Settings(**{**PROD_ENV, "RESEND_API_KEY": ""})


def test_production_rejects_wildcard_hosts():
    import pytest

    with pytest.raises(ValueError, match="ALLOWED_HOSTS"):
        Settings(**{**PROD_ENV, "ALLOWED_HOSTS": "*"})


def test_railway_database_url_is_coerced_to_asyncpg():
    settings = Settings(DATABASE_URL="postgresql://u:p@host:5432/db")
    assert settings.DATABASE_URL.startswith("postgresql+asyncpg://")
    assert settings.sync_database_url.startswith("postgresql://")
