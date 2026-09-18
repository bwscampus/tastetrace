"""Auth over bearer tokens, the profile screen, and settings."""

from tests.conftest_project import PASSWORD, register_and_login


async def test_bearer_login_returns_a_token_that_identifies_the_user(client):
    auth = await register_and_login(client, "taylor@example.com")

    me = await client.get("/api/users/me", headers=auth)
    assert me.status_code == 200
    assert me.json()["email"] == "taylor@example.com"
    # Project columns are exposed camelCase alongside fastapi-users' own fields
    assert me.json()["sensitivityTags"] == []
    assert me.json()["isActive"] is True

    assert (await client.get("/api/users/me")).status_code == 401


async def test_bearer_logout_revokes_the_token(client):
    auth = await register_and_login(client, "taylor@example.com")
    assert (await client.post("/api/auth/bearer/logout", headers=auth)).status_code == 204
    assert (await client.get("/api/users/me", headers=auth)).status_code == 401


async def test_wrong_password_does_not_issue_a_token(client):
    await register_and_login(client, "taylor@example.com")
    response = await client.post(
        "/api/auth/bearer/login",
        data={"username": "taylor@example.com", "password": "not the password"},
    )
    assert response.status_code == 400


async def test_profile_reports_journaling_span_and_accepts_edits(client):
    auth = await register_and_login(client, "taylor@example.com")

    profile = (await client.get("/api/profile", headers=auth)).json()
    assert profile["email"] == "taylor@example.com"
    assert profile["journalerDays"] >= 1
    assert profile["firstLogAt"] is None
    assert profile["sensitivityTags"] == []

    patched = await client.patch(
        "/api/profile",
        headers=auth,
        json={"displayName": "Taylor", "sensitivityTags": ["gluten"], "discoveryPurpose": "Find triggers"},
    )
    assert patched.status_code == 200
    assert patched.json()["displayName"] == "Taylor"
    assert patched.json()["sensitivityTags"] == ["gluten"]
    assert (await client.get("/api/profile", headers=auth)).json()["discoveryPurpose"] == "Find triggers"


async def test_settings_start_at_the_documented_defaults(client):
    auth = await register_and_login(client, "taylor@example.com")

    settings = (await client.get("/api/settings", headers=auth)).json()
    assert settings["correlationWindowHours"] == 24
    assert settings["minTriggerCount"] == 2
    assert settings["minConfidence"] == 50
    assert settings["streakMealsPerDay"] == 2
    assert settings["nudgeTime"] == "20:30"
    assert settings["nudgesEnabled"] is True
    assert settings["timezone"] == "UTC"


async def test_settings_validate_timezone_and_ranges(client):
    auth = await register_and_login(client, "taylor@example.com")

    ok = await client.patch(
        "/api/settings",
        headers=auth,
        json={"timezone": "America/Los_Angeles", "streakMealsPerDay": 3},
    )
    assert ok.status_code == 200
    assert ok.json()["timezone"] == "America/Los_Angeles"
    assert ok.json()["streakMealsPerDay"] == 3

    bad_zone = await client.patch("/api/settings", headers=auth, json={"timezone": "Mars/Olympus"})
    assert bad_zone.status_code == 400
    assert bad_zone.json()["detail"] == "Unknown timezone"

    assert (await client.patch("/api/settings", headers=auth, json={"minConfidence": 200})).status_code == 422
    assert (await client.patch("/api/settings", headers=auth, json={"nudgeTime": "25:00"})).status_code == 422


async def test_settings_are_per_user(client):
    alice = await register_and_login(client, "alice@example.com")
    bob = await register_and_login(client, "bob@example.com")

    await client.patch("/api/settings", headers=alice, json={"streakMealsPerDay": 5})
    assert (await client.get("/api/settings", headers=bob)).json()["streakMealsPerDay"] == 2


async def test_password_policy_is_the_template_minimum(client):
    short = await client.post(
        "/api/auth/register", json={"email": "short@example.com", "password": "abc123"}
    )
    assert short.status_code == 400
    assert "at least 8" in short.text
