"""The medical disclaimer: served, accepted, and required before onboarding ends.

The gate is enforced here rather than only in the app. A disclaimer someone can
walk past by using an old build is not a disclaimer, and this record is the only
evidence that it was ever agreed to.
"""

from app.domain.disclaimer import (
    DISCLAIMER_TEXT,
    DISCLAIMER_VERSION,
    SEVERE_INTENSITY,
)
from app.domain.severity import SEVERE, severity_from_intensity
from tests.conftest_project import register_and_login


async def test_the_text_is_served_so_the_app_never_keeps_its_own_copy(client):
    response = await client.get("/api/legal/disclaimer")
    assert response.status_code == 200
    body = response.json()
    assert body["version"] == DISCLAIMER_VERSION
    assert body["text"] == DISCLAIMER_TEXT
    # The substance the wording has to carry, so an edit that drops any of it fails here.
    assert "not a diagnostic tool" in body["text"]
    assert "does not replace medical care" in body["text"]
    assert "not reviewed by a medical professional" in body["text"]
    assert "seek medical attention" in body["text"]


async def test_a_new_account_has_accepted_nothing(client):
    auth = await register_and_login(client, "taylor@example.com")
    me = (await client.get("/api/profile", headers=auth)).json()
    assert me["disclaimerVersion"] is None
    assert me["disclaimerAcceptedAt"] is None


async def test_onboarding_cannot_complete_without_accepting(client):
    auth = await register_and_login(client, "taylor@example.com")

    refused = await client.patch(
        "/api/profile", headers=auth, json={"onboardingCompleted": True}
    )
    assert refused.status_code == 400
    assert "disclaimer" in refused.json()["detail"].lower()

    # And it really did not complete, rather than erroring after the fact.
    me = (await client.get("/api/profile", headers=auth)).json()
    assert me["onboardingCompletedAt"] is None


async def test_accepting_records_the_version_and_the_time(client):
    auth = await register_and_login(client, "taylor@example.com")
    accepted = await client.patch(
        "/api/profile", headers=auth, json={"acceptDisclaimerVersion": DISCLAIMER_VERSION}
    )
    assert accepted.status_code == 200
    body = accepted.json()
    assert body["disclaimerVersion"] == DISCLAIMER_VERSION
    assert body["disclaimerAcceptedAt"] is not None
    # Accepting alone does not finish onboarding; the rest of the flow still runs.
    assert body["onboardingCompletedAt"] is None


async def test_onboarding_completes_once_accepted(client):
    auth = await register_and_login(client, "taylor@example.com")
    await client.patch(
        "/api/profile", headers=auth, json={"acceptDisclaimerVersion": DISCLAIMER_VERSION}
    )
    done = await client.patch("/api/profile", headers=auth, json={"onboardingCompleted": True})
    assert done.status_code == 200
    assert done.json()["onboardingCompletedAt"] is not None


async def test_accepting_and_completing_in_one_call_works(client):
    """What the app actually sends on the last onboarding screen."""
    auth = await register_and_login(client, "taylor@example.com")
    done = await client.patch(
        "/api/profile",
        headers=auth,
        json={"acceptDisclaimerVersion": DISCLAIMER_VERSION, "onboardingCompleted": True},
    )
    assert done.status_code == 200
    assert done.json()["disclaimerVersion"] == DISCLAIMER_VERSION
    assert done.json()["onboardingCompletedAt"] is not None


async def test_an_old_version_is_refused_rather_than_recorded(client):
    """A stale build must not log agreement to wording nobody is showing."""
    auth = await register_and_login(client, "taylor@example.com")
    stale = await client.patch(
        "/api/profile", headers=auth, json={"acceptDisclaimerVersion": "2020-01-01"}
    )
    assert stale.status_code == 409
    me = (await client.get("/api/profile", headers=auth)).json()
    assert me["disclaimerVersion"] is None


async def test_an_account_that_accepted_an_old_version_must_accept_again(client, engine):
    """Changing the wording re-asks; it does not carry the old agreement over."""
    from sqlalchemy import update

    from app.auth.models import User

    auth = await register_and_login(client, "taylor@example.com")
    async with engine.begin() as connection:
        await connection.execute(update(User).values(disclaimer_version="2020-01-01"))

    refused = await client.patch(
        "/api/profile", headers=auth, json={"onboardingCompleted": True}
    )
    assert refused.status_code == 400


async def test_the_severe_threshold_matches_the_severity_scale(client):
    """The wording promises severe symptoms get directed to medical care.

    If these two ever disagree, the app would show that guidance at the wrong
    point and the promise would be wrong in one direction or the other.
    """
    assert severity_from_intensity(SEVERE_INTENSITY) == SEVERE
    assert severity_from_intensity(SEVERE_INTENSITY - 1) != SEVERE
