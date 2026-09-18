"""The interpreting endpoints, over real HTTP."""

from tests.conftest_project import register_and_login

TZ = "America/Los_Angeles"


async def seed_week(client, auth) -> None:
    """The mockup's week: toast twice, each followed by reflux and bloating."""
    for day in ("2026-09-11", "2026-09-17"):
        await client.post(
            "/api/meals",
            headers=auth,
            json={
                "name": "Avocado Sourdough Toast",
                "mealType": "Lunch",
                "timestamp": f"{day}T19:45:00Z",
                "tz": TZ,
                "ingredientDetails": [
                    {"name": "sourdough bread", "cookMethod": "toasted"},
                    {"name": "avocado"},
                    {"name": "salt"},
                ],
            },
        )
        await client.post(
            "/api/symptoms/batch",
            headers=auth,
            json={
                "timestamp": f"{day}T21:29:00Z",
                "tz": TZ,
                "durationMinutes": 60,
                "items": [
                    {"name": "Acid Reflux", "catalogKey": "acid_reflux", "intensity": 3},
                    {"name": "Bloating", "catalogKey": "bloating", "intensity": 1},
                ],
            },
        )


async def test_coverage_reports_slots_streak_and_the_week(client):
    auth = await register_and_login(client, "taylor@example.com")
    await client.post(
        "/api/meals",
        headers=auth,
        json={"name": "Oats", "mealType": "Breakfast", "timestamp": "2026-09-17T15:15:00Z", "tz": TZ},
    )

    coverage = await client.get("/api/coverage", headers=auth, params={"date": "2026-09-17", "tz": TZ})
    assert coverage.status_code == 200, coverage.text
    body = coverage.json()
    assert body["slots"]["Breakfast"]["logged"] is True
    assert body["slots"]["Breakfast"]["time"] == "08:15"
    assert body["slots"]["Dinner"]["logged"] is False
    assert body["slotTotal"] == 3
    assert body["percent"] == 33
    assert len(body["week"]) == 7
    assert body["streak"]["threshold"] == 2
    assert body["weekSlots"]["total"] == 21
    assert body["nudge"] == {"time": "20:30", "enabled": True}

    assert (await client.get("/api/coverage", headers=auth, params={"date": "nope"})).status_code == 400


async def test_the_weekly_digest_scores_the_week(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    digest = await client.get(
        "/api/digest/weekly", headers=auth, params={"weekStart": "2026-09-11", "tz": TZ}
    )
    assert digest.status_code == 200, digest.text
    body = digest.json()
    assert body["weekEnd"] == "2026-09-17"
    assert len(body["trends"]["days"]) == 7
    assert body["trends"]["days"][0]["date"] == "2026-09-11"
    assert [day["index"] for day in body["trends"]["days"]] == [6, 0, 0, 0, 0, 0, 6]
    assert body["trends"]["index"] == 1.7
    assert body["trends"]["flares"] == 2
    assert body["trends"]["severePeakDay"] == "2026-09-11"

    reflux = next(card for card in body["symptoms"]["cards"] if card["name"] == "Acid Reflux")
    assert reflux["emoji"] == "🔥"
    assert reflux["avgSeverity10"] == 6
    assert reflux["avgDurationMinutes"] == 60
    assert reflux["shareOfWeek"] == 0.5
    assert body["symptoms"]["onsetWindows"]["from1to3h"] == 4

    assert (await client.get("/api/digest/weekly", headers=auth, params={"weekStart": "bad"})).status_code == 400
    assert (await client.get("/api/digest/weekly", headers=auth)).status_code == 200


async def test_the_suspects_digest_ranks_ingredients_before_flares(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    suspects = await client.get(
        "/api/digest/suspects", headers=auth, params={"weekStart": "2026-09-11", "tz": TZ}
    )
    assert suspects.status_code == 200, suspects.text
    body = suspects.json()
    assert body["windowHours"] == 24
    assert body["flares"] == 2
    assert body["symptomFilters"][0]["name"] == "All Symptoms"
    # Every ingredient of the toast preceded both flares, so they tie on share
    # and confidence and the order falls back to the name.
    assert {i["name"] for i in body["ingredients"]} == {"sourdough bread", "avocado", "salt"}
    assert body["leadSuspect"] == body["ingredients"][0]["name"] == "avocado"

    sourdough = next(i for i in body["ingredients"] if i["name"] == "sourdough bread")
    assert sourdough["flaresWithIngredient"] == 2
    assert sourdough["share"] == 1
    assert sourdough["avgOnsetHours"] == 1.7  # rounded to one decimal, as the app shows it
    assert sourdough["onWatchlist"] is False
    assert sourdough["recentPairs"][0]["symptoms"] == ["Acid Reflux", "Bloating"]

    # The window keys are data, so they keep the shape the client decodes
    assert body["timingWindows"]["0to4h"]["flares"] == 2
    assert body["timingWindows"]["12to24h"]["flares"] == 0


async def test_trigger_insights_rank_by_confidence_and_respect_the_floor(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    insights = await client.get(
        "/api/insights/triggers", headers=auth, params={"dimension": "ingredient", "minConfidence": 0}
    )
    assert insights.status_code == 200, insights.text
    body = insights.json()
    assert body["dimension"] == "ingredient"
    assert body["minConfidence"] == 0
    assert body["windowHours"] == 24
    assert {s["name"] for s in body["symptoms"]} == {"Acid Reflux", "Bloating"}
    assert any(card["item"] == "sourdough bread" for card in body["cards"])

    card = next(c for c in body["cards"] if c["item"] == "sourdough bread")
    assert card["exposures"] == 2
    assert card["flareExposures"] == 2
    assert card["tier"] in {"strong", "likely", "watch"}
    assert card["evidence"], "a card should show the meals behind it"

    # The default floor of 50 hides the same rows
    hidden = await client.get("/api/insights/triggers", headers=auth)
    assert hidden.json()["minConfidence"] == 50

    cooking = await client.get(
        "/api/insights/triggers", headers=auth, params={"dimension": "cook_method", "minConfidence": 0}
    )
    assert any(card["item"] == "toasted" for card in cooking.json()["cards"])

    assert (await client.get("/api/insights/triggers", headers=auth, params={"minConfidence": 200})).status_code == 400


async def test_the_watchlist_normalises_entries_and_reports_confidence(client):
    auth = await register_and_login(client, "taylor@example.com")
    await seed_week(client, auth)

    added = await client.post(
        "/api/watchlist", headers=auth, json={"ingredient": "Sourdough Bread", "source": "suspect"}
    )
    assert added.status_code == 201
    assert added.json()["ingredient"] == "sourdough bread"

    listed = (await client.get("/api/watchlist", headers=auth)).json()
    assert listed[0]["source"] == "suspect"
    assert listed[0]["confidenceMax"] > 0, "the seeded week produces an association"

    # Adding the same ingredient again updates rather than duplicates
    await client.post("/api/watchlist", headers=auth, json={"ingredient": "sourdough  bread"})
    assert len((await client.get("/api/watchlist", headers=auth)).json()) == 1

    suspects = await client.get(
        "/api/digest/suspects", headers=auth, params={"weekStart": "2026-09-11", "tz": TZ}
    )
    watched = next(i for i in suspects.json()["ingredients"] if i["name"] == "sourdough bread")
    assert watched["onWatchlist"] is True

    assert (await client.delete(f"/api/watchlist/{listed[0]['id']}", headers=auth)).status_code == 204
    assert (await client.delete("/api/watchlist/999", headers=auth)).status_code == 404
