"""Ported from app/test/api.test.ts: the write paths and their rules."""

from tests.conftest_project import register_and_login

TZ = "America/Los_Angeles"


async def test_symptoms_store_both_scales_the_client_timestamp_and_the_local_day(client):
    auth = await register_and_login(client, "taylor@example.com")

    created = await client.post(
        "/api/symptoms",
        headers=auth,
        json={
            "name": "Acid Reflux",
            "catalogKey": "acid_reflux",
            "intensity": 3,
            "timestamp": "2026-09-11T21:29:00Z",
            "tz": TZ,
            "durationMinutes": 60,
        },
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["severity"] == "Moderate"
    assert body["intensity"] == 3
    assert body["date"] == "2026-09-11"  # 2:29pm in Los Angeles, not the UTC day
    assert body["timestamp"] == "2026-09-11T21:29:00.000Z"
    assert body["emoji"] == "🔥"

    # A severity-only write (how the web app logs) gets an intensity derived
    web_style = await client.post(
        "/api/symptoms", headers=auth, json={"name": "Headache", "severity": "Severe"}
    )
    assert web_style.status_code == 201
    assert web_style.json()["intensity"] == 4

    moved = await client.put(
        f"/api/symptoms/{body['id']}",
        headers=auth,
        json={"timestamp": "2026-09-12T22:00:00Z", "tz": TZ},
    )
    assert moved.status_code == 200
    assert moved.json()["date"] == "2026-09-12"

    assert (await client.post("/api/symptoms", headers=auth, json={"name": "x", "intensity": 9})).status_code == 422
    assert (await client.post("/api/symptoms", headers=auth, json={"name": "x"})).status_code == 422


async def test_quick_log_posts_several_symptoms_at_one_moment(client):
    auth = await register_and_login(client, "taylor@example.com")

    batch = await client.post(
        "/api/symptoms/batch",
        headers=auth,
        json={
            "timestamp": "2026-09-11T21:29:00Z",
            "tz": TZ,
            "items": [
                {"name": "Acid Reflux", "catalogKey": "acid_reflux", "intensity": 3},
                {"name": "Bloating", "catalogKey": "bloating", "intensity": 1},
            ],
        },
    )
    assert batch.status_code == 201, batch.text
    assert len(batch.json()) == 2
    assert batch.json()[1]["severity"] == "Mild"
    assert batch.json()[1]["emoji"] == "🎈"


async def test_the_symptom_catalog_carries_the_six_defaults_and_custom_additions(client):
    auth = await register_and_login(client, "taylor@example.com")

    catalog = await client.get("/api/symptom-catalog", headers=auth)
    assert len(catalog.json()["defaults"]) == 6
    assert catalog.json()["custom"] == []

    added = await client.post("/api/symptom-catalog", headers=auth, json={"name": "Brain Fog"})
    assert added.status_code == 201
    assert added.json()["key"] == "custom:brain-fog"

    assert len((await client.get("/api/symptom-catalog", headers=auth)).json()["custom"]) == 1
    assert (await client.delete(f"/api/symptom-catalog/{added.json()['id']}", headers=auth)).status_code == 204


async def test_meal_ingredients_come_from_the_detailed_list(client):
    auth = await register_and_login(client, "taylor@example.com")

    meal = await client.post(
        "/api/meals",
        headers=auth,
        json={
            "name": "Avocado Sourdough Toast",
            "mealType": "Lunch",
            "tz": TZ,
            "timestamp": "2026-09-11T19:45:00Z",
            "ingredientDetails": [
                {"name": "sourdough bread", "cookMethod": "toasted"},
                {"name": "avocado"},
            ],
        },
    )
    assert meal.status_code == 201, meal.text
    assert meal.json()["ingredients"] == ["sourdough bread", "avocado"]
    assert meal.json()["ingredientDetails"][0]["cookMethod"] == "toasted"
    assert meal.json()["date"] == "2026-09-11"

    # Editing notes must not rewrite the list the user curated
    edited = await client.put(
        f"/api/meals/{meal.json()['id']}", headers=auth, json={"notes": "with, extra, commas"}
    )
    assert edited.json()["ingredients"] == ["sourdough bread", "avocado"]


async def test_entries_belong_to_their_owner_alone(client):
    alice = await register_and_login(client, "alice@example.com")
    bob = await register_and_login(client, "bob@example.com")

    meal = await client.post("/api/meals", headers=alice, json={"name": "Pizza", "mealType": "Dinner"})
    meal_id = meal.json()["id"]

    # A stranger is told it does not exist, never that it is forbidden
    assert (await client.get(f"/api/meals/{meal_id}", headers=bob)).status_code == 404
    assert (await client.put(f"/api/meals/{meal_id}", headers=bob, json={"name": "x"})).status_code == 404
    assert (await client.delete(f"/api/meals/{meal_id}", headers=bob)).status_code == 404
    assert (await client.get(f"/api/meals/{meal_id}", headers=alice)).status_code == 200

    symptom = await client.post("/api/symptoms", headers=alice, json={"name": "Bloating", "intensity": 2})
    assert (await client.delete(f"/api/symptoms/{symptom.json()['id']}", headers=bob)).status_code == 404


async def test_a_dish_tile_logs_a_meal_and_counts_its_use(client):
    auth = await register_and_login(client, "taylor@example.com")

    dish = await client.post(
        "/api/dishes",
        headers=auth,
        json={
            "name": "Avocado Sourdough Toast",
            "emoji": "🥑",
            "containsGluten": True,
            "ingredients": [
                {"name": "sourdough bread", "cookMethod": "toasted"},
                {"name": "avocado", "cookMethod": "raw"},
                {"name": "salt"},
            ],
        },
    )
    assert dish.status_code == 201, dish.text
    assert dish.json()["timesLogged"] == 0
    dish_id = dish.json()["id"]

    logged = await client.post(
        f"/api/dishes/{dish_id}/log",
        headers=auth,
        json={"mealType": "Lunch", "timestamp": "2026-09-11T19:45:00Z", "tz": TZ},
    )
    assert logged.status_code == 201, logged.text
    assert logged.json()["dishId"] == dish_id
    assert logged.json()["ingredients"] == ["sourdough bread", "avocado", "salt"]
    assert logged.json()["ingredientDetails"][0]["cookMethod"] == "toasted"
    assert logged.json()["containsGluten"] is True
    assert logged.json()["date"] == "2026-09-11"

    listed = (await client.get("/api/dishes", headers=auth)).json()
    assert listed[0]["timesLogged"] == 1
    assert listed[0]["lastLoggedAt"] == "2026-09-11T19:45:00.000Z"

    assert (await client.post(f"/api/dishes/{dish_id}/log", headers=auth, json={"mealType": "Brunch"})).status_code == 422

    renamed = await client.put(f"/api/dishes/{dish_id}", headers=auth, json={"emoji": "🍞"})
    assert renamed.json()["emoji"] == "🍞"

    # Deleting the tile keeps the meal that came from it
    assert (await client.delete(f"/api/dishes/{dish_id}", headers=auth)).status_code == 204
    assert (await client.get(f"/api/meals/{logged.json()['id']}", headers=auth)).json()["dishId"] is None


async def test_a_day_shows_its_entries_flares_and_suspicious_meals(client):
    auth = await register_and_login(client, "taylor@example.com")

    meal = await client.post(
        "/api/meals",
        headers=auth,
        json={
            "name": "Late pizza",
            "mealType": "Dinner",
            "timestamp": "2026-09-20T02:00:00Z",
            "tz": TZ,
            "ingredientDetails": [{"name": "cheese"}],
        },
    )
    await client.post(
        "/api/symptoms",
        headers=auth,
        json={"name": "Bloating", "intensity": 2, "timestamp": "2026-09-20T04:00:00Z", "tz": TZ},
    )

    # 02:00Z on the 20th is 7pm on the 19th in Los Angeles
    day = await client.get("/api/entries/date", headers=auth, params={"date": "2026-09-19", "tz": TZ})
    assert day.status_code == 200, day.text
    flagged = next(m for m in day.json()["meals"] if m["id"] == meal.json()["id"])
    assert flagged["suspiciousFor"] == ["Bloating"]
    assert flagged["suspicion"] in {"window", "correlated"}
    assert day.json()["flares"] == 1
    assert len(day.json()["symptoms"]) == 1
    assert day.json()["entries"] == 2

    assert (await client.get("/api/entries/date", headers=auth, params={"date": "nope"})).status_code == 400


async def test_markers_colour_the_calendar_by_what_was_logged(client):
    auth = await register_and_login(client, "taylor@example.com")
    await client.post(
        "/api/meals",
        headers=auth,
        json={"name": "Oats", "mealType": "Breakfast", "timestamp": "2026-09-17T15:15:00Z", "tz": TZ},
    )
    await client.post(
        "/api/symptoms",
        headers=auth,
        json={"name": "Headache", "intensity": 4, "timestamp": "2026-09-18T15:15:00Z", "tz": TZ},
    )

    markers = await client.get(
        "/api/entries/markers",
        headers=auth,
        params={"start": "2026-09-01T00:00:00Z", "end": "2026-09-30T00:00:00Z", "tz": TZ},
    )
    assert markers.status_code == 200, markers.text
    body = markers.json()
    assert body["2026-09-17"] == {"meals": 1, "symptoms": 0, "maxIntensity": 0, "status": "meal"}
    assert body["2026-09-18"]["status"] == "symptom"
    assert body["2026-09-18"]["maxIntensity"] == 4

    assert (await client.get("/api/entries/markers", headers=auth, params={"start": "x", "end": "y"})).status_code == 400
