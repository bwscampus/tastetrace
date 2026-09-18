"""Ported from app/test/rules.test.ts."""

from app.ai.rules import rules_synthesis
from app.domain.suspects import Suspect, SuspectsDigest, TimingWindow


def digest(**overrides) -> SuspectsDigest:
    base = dict(
        week_start="2026-09-11",
        week_end="2026-09-17",
        window_hours=24,
        flares=2,
        meals_evaluated=2,
        lead_suspect="sourdough bread",
        symptom_filters=[],
        ingredients=[],
        timing_windows={
            "0to4h": TimingWindow(flares=2),
            "4to12h": TimingWindow(),
            "12to24h": TimingWindow(),
        },
    )
    return SuspectsDigest(**{**base, **overrides})


def test_it_describes_the_lead_suspect_with_its_own_numbers():
    result = rules_synthesis(
        digest(
            ingredients=[
                Suspect(
                    name="sourdough bread",
                    flares_with_ingredient=1,
                    flares_total=2,
                    share=0.5,
                    avg_onset_hours=1.7,
                    times_logged_this_week=1,
                    exposures_all_time=6,
                    confidence=38,
                    on_watchlist=False,
                    recent_pairs=[],
                )
            ]
        )
    )
    assert "sourdough bread appeared in 1 of 2 flare windows (50%)" in result.text
    assert "1.7 hours" in result.text
    assert "observed associations" in result.text
    assert result.suggested_watchlist == ["sourdough bread"]


def test_it_says_plainly_when_there_is_nothing_to_correlate():
    assert "No flare-ups" in rules_synthesis(digest(flares=0)).text
    assert "no meals were recorded" in rules_synthesis(digest()).text
