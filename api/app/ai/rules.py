"""The written summary, without a model.

Used when no API key is configured, when the model declines or errors, and as
the source of `suggestedWatchlist` in every case. The tone is deliberately
hedged: these are associations in a small sample, not findings.
"""

from dataclasses import dataclass

from app.domain.suspects import SuspectsDigest

# Below this many flares the sample is small enough to say so plainly
FEW_FLARES = 4
# A suspect present before at least half the flares is worth offering to track
WATCHLIST_SHARE = 0.5


@dataclass
class RulesSynthesis:
    text: str
    suggested_watchlist: list[str]


def rules_synthesis(suspects: SuspectsDigest) -> RulesSynthesis:
    if suspects.flares == 0:
        return RulesSynthesis(
            text=(
                "No flare-ups were logged in this window, so there is nothing to "
                "correlate yet. Keep logging meals and symptoms and this summary "
                "will describe what tends to come before your flares."
            ),
            suggested_watchlist=[],
        )

    if not suspects.ingredients:
        plural = "" if suspects.flares == 1 else "s"
        return RulesSynthesis(
            text=(
                f"{suspects.flares} flare{plural} were logged, but no meals were "
                f"recorded in the {suspects.window_hours} hours before them, so no "
                "ingredient can be linked yet. Logging meals around flare times will "
                "make the next summary more useful."
            ),
            suggested_watchlist=[],
        )

    lead = suspects.ingredients[0]
    share = round(lead.share * 100)
    onset = (
        f"an average meal-to-flare delay of {lead.avg_onset_hours} hours"
        if lead.avg_onset_hours is not None
        else "no clear onset timing"
    )
    others = [s.name for s in suspects.ingredients[1:3]]
    others_text = f" {' and '.join(others)} also appeared before flares." if others else ""
    caveat = (
        " These are only observed associations rather than proof of a trigger, and the "
        "small number of windows means there is still considerable uncertainty."
        if suspects.flares < FEW_FLARES
        else " These are observed associations, not proof of a trigger; a consistent "
        "pattern across more weeks would make the link stronger."
    )
    return RulesSynthesis(
        text=(
            f"In the {suspects.window_hours}-hour lookback before flares, {lead.name} "
            f"appeared in {lead.flares_with_ingredient} of {lead.flares_total} flare "
            f"windows ({share}%), with {onset}.{others_text}{caveat}"
        ),
        suggested_watchlist=[lead.name]
        if lead.share >= WATCHLIST_SHARE and not lead.on_watchlist
        else [],
    )
