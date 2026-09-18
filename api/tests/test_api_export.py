"""The AI summary and the two exports."""

from tests.conftest_project import register_and_login
from tests.test_api_analytics import seed_week

TZ = "America/Los_Angeles"


async def test_the_summary_is_written_without_a_model_and_then_cached(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    first = await client.post(
        "/api/ai/synthesis", headers=auth, json={"weekStart": "2026-09-11", "tz": TZ}
    )
    assert first.status_code == 200, first.text
    body = first.json()
    # No ANTHROPIC_API_KEY in the test environment, so the template writes it
    assert body["source"] == "rules"
    assert body["model"] is None
    assert body["cached"] is False
    assert len(body["text"]) > 20
    assert "flare windows" in body["text"]

    again = await client.post(
        "/api/ai/synthesis", headers=auth, json={"weekStart": "2026-09-11", "tz": TZ}
    )
    assert again.json()["cached"] is True
    assert again.json()["text"] == body["text"]

    quiet = await client.post(
        "/api/ai/synthesis", headers=auth, json={"weekStart": "2026-10-05", "tz": TZ}
    )
    assert "No flare-ups" in quiet.json()["text"]

    assert (await client.post("/api/ai/synthesis", headers=auth, json={"weekStart": "nope"})).status_code == 400


async def test_the_csv_export_has_a_stable_header_and_one_row_per_entry(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    response = await client.get(
        "/api/export/csv", headers=auth, params={"from": "2026-09-01", "to": "2026-09-30", "tz": TZ}
    )
    assert response.status_code == 200, response.text
    assert "text/csv" in response.headers["content-type"]
    assert 'filename="tastetrace-2026-09-01-2026-09-30.csv"' in response.headers["content-disposition"]

    lines = response.text.strip().split("\n")
    assert lines[0] == (
        "entry_type,id,date,time,name,meal_type,ingredients,cook_methods,dish,"
        "intensity,severity,duration_minutes,notes,timestamp_utc"
    )
    assert any(
        line.startswith("meal,") and "Avocado Sourdough Toast" in line and "sourdough bread; avocado" in line
        for line in lines
    )
    assert any(line.startswith("symptom,") and "Acid Reflux" in line for line in lines)
    # Two meals and four symptoms were seeded
    assert len(lines) == 7

    assert (
        await client.get("/api/export/csv", headers=auth, params={"from": "2026-09-30", "to": "2026-09-01"})
    ).status_code == 400


async def test_the_csv_quotes_only_cells_that_need_it(client):
    auth = await register_and_login(client, "taylor@example.com")
    await client.post(
        "/api/meals",
        headers=auth,
        json={
            "name": 'Toast, "the good kind"',
            "mealType": "Lunch",
            "timestamp": "2026-09-11T19:45:00Z",
            "tz": TZ,
            "notes": "line one\nline two",
        },
    )

    response = await client.get(
        "/api/export/csv", headers=auth, params={"from": "2026-09-11", "to": "2026-09-11", "tz": TZ}
    )
    assert '"Toast, ""the good kind"""' in response.text
    assert '"line one\nline two"' in response.text


async def test_the_ledger_bundle_carries_everything_the_reports_render(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)
    await client.patch("/api/profile", headers=auth, json={"displayName": "Taylor"})

    response = await client.get(
        "/api/export/ledger", headers=auth, params={"from": "2026-09-01", "to": "2026-09-30", "tz": TZ}
    )
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["range"] == {"from": "2026-09-01", "to": "2026-09-30", "tz": TZ}
    assert body["profile"]["displayName"] == "Taylor"
    assert body["profile"]["email"] == "taylor@example.com"
    assert body["totals"] == {"meals": 2, "symptoms": 4, "days": 2}
    assert [day["date"] for day in body["days"]] == ["2026-09-11", "2026-09-17"]
    assert body["days"][0]["flares"] == 1
    assert body["days"][0]["meals"][0]["suspiciousFor"] == ["Acid Reflux", "Bloating"]
    assert body["settings"]["correlationWindowHours"] == 24
    assert isinstance(body["triggers"], list)
    assert len(body["digestWeeks"]) >= 1
    assert body["digestWeeks"][0]["trends"]["days"][0]["date"]
