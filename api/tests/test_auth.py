"""The auth flows that matter: sign in, stay signed in, reset, get signed out."""

import re

import pytest

from app.config import settings


async def login(client, credentials):
    return await client.post(
        "/api/auth/login",
        data={
            "username": credentials["email"],
            "password": credentials["password"],
        },
    )


async def test_register_login_me_logout(client, credentials, registered):
    response = await login(client, credentials)
    assert response.status_code == 204, response.text

    cookie = response.cookies.get(settings.SESSION_COOKIE_NAME)
    assert cookie, "login must set the session cookie"

    me = await client.get("/api/users/me")
    assert me.status_code == 200
    assert me.json()["email"] == credentials["email"]

    assert (await client.post("/api/auth/logout")).status_code == 204
    assert (await client.get("/api/users/me")).status_code == 401


async def test_session_cookie_is_not_readable_by_javascript(
    client, credentials, registered
):
    response = await login(client, credentials)
    set_cookie = response.headers["set-cookie"].lower()
    assert "httponly" in set_cookie
    assert "samesite=lax" in set_cookie


async def test_wrong_password_is_rejected(client, credentials, registered):
    response = await login(
        client, {**credentials, "password": "not the password"}
    )
    assert response.status_code == 400


async def test_forgot_password_does_not_reveal_whether_account_exists(
    client, registered
):
    known = await client.post(
        "/api/auth/forgot-password", json={"email": "athlete@example.com"}
    )
    unknown = await client.post(
        "/api/auth/forgot-password", json={"email": "nobody@example.com"}
    )
    assert known.status_code == unknown.status_code == 202
    assert known.text == unknown.text


async def test_reset_password_works_and_revokes_existing_sessions(
    client, credentials, registered, monkeypatch
):
    """The payoff of database-backed sessions.

    A stolen session must stop working the moment the password is reset.
    """
    sent: dict[str, str] = {}

    async def fake_send_email(to, subject, html):
        sent["html"] = html

    monkeypatch.setattr("app.auth.users.send_email", fake_send_email)

    # Sign in, and confirm the session works.
    await login(client, credentials)
    assert (await client.get("/api/users/me")).status_code == 200

    await client.post(
        "/api/auth/forgot-password", json={"email": credentials["email"]}
    )
    match = re.search(r"reset_token=([^\"&\s<]+)", sent["html"])
    assert match, "reset email must contain a token link"
    token = match.group(1)

    reset = await client.post(
        "/api/auth/reset-password",
        json={"token": token, "password": "a whole new password"},
    )
    assert reset.status_code == 200, reset.text

    # The pre-reset session must now be dead.
    assert (await client.get("/api/users/me")).status_code == 401

    # And the new password must work.
    assert (
        await login(client, {**credentials, "password": "a whole new password"})
    ).status_code == 204


async def test_reset_token_is_single_use(
    client, credentials, registered, monkeypatch
):
    sent: dict[str, str] = {}

    async def fake_send_email(to, subject, html):
        sent["html"] = html

    monkeypatch.setattr("app.auth.users.send_email", fake_send_email)
    await client.post(
        "/api/auth/forgot-password", json={"email": credentials["email"]}
    )
    token = re.search(r"reset_token=([^\"&\s<]+)", sent["html"]).group(1)

    first = await client.post(
        "/api/auth/reset-password", json={"token": token, "password": "first pw"}
    )
    assert first.status_code == 200
    second = await client.post(
        "/api/auth/reset-password",
        json={"token": token, "password": "second pw"},
    )
    assert second.status_code == 400


@pytest.mark.parametrize("attempts", [12])
async def test_login_is_rate_limited(client, credentials, registered, attempts):
    statuses = []
    for _ in range(attempts):
        response = await login(
            client, {**credentials, "password": "wrong guess"}
        )
        statuses.append(response.status_code)
    assert 429 in statuses, "repeated failed logins must eventually be limited"


async def test_short_passwords_are_rejected(client):
    response = await client.post(
        "/api/auth/register",
        json={"email": "new@example.com", "password": "short"},
    )
    assert response.status_code == 400
    assert "8 characters" in response.text


async def test_password_cannot_contain_the_email(client):
    response = await client.post(
        "/api/auth/register",
        json={
            "email": "athlete@example.com",
            "password": "athlete@example.com!!",
        },
    )
    assert response.status_code == 400
    assert "email address" in response.text


async def test_forgot_password_still_202s_when_email_delivery_fails(
    client, credentials, registered, monkeypatch
):
    """A broken mail provider must not become an account-enumeration oracle."""

    async def exploding_send_email(to, subject, html):
        raise RuntimeError("Resend is down / API key is wrong")

    monkeypatch.setattr("app.auth.users.send_email", exploding_send_email)

    known = await client.post(
        "/api/auth/forgot-password", json={"email": credentials["email"]}
    )
    unknown = await client.post(
        "/api/auth/forgot-password", json={"email": "nobody@example.com"}
    )
    assert known.status_code == unknown.status_code == 202
