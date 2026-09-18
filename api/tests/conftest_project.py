"""Helpers for the project's own tests (the template's conftest stays intact)."""

from httpx import AsyncClient

PASSWORD = "correct horse battery"


async def register_and_login(client: AsyncClient, email: str) -> dict[str, str]:
    """Creates an account and returns an Authorization header for it."""
    response = await client.post(
        "/api/auth/register", json={"email": email, "password": PASSWORD}
    )
    assert response.status_code == 201, response.text
    login = await client.post(
        "/api/auth/bearer/login", data={"username": email, "password": PASSWORD}
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
