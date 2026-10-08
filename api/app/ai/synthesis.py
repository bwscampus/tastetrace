"""The written summary on the Food Suspect Digest.

A model is used when one is configured; otherwise, and on any failure, the
template in rules.py writes it instead. The endpoint never fails because of the
model.

Only the model's prose is cached, against a hash of the numbers it describes, so
re-opening the screen costs nothing and the text changes only when the data
does. The template is never stored: it is what a cache miss looks like, it costs
nothing to rewrite, and storing it would stop the model ever being asked again
for that week.
"""

import hashlib
import json
import logging
import time
from dataclasses import asdict
from datetime import UTC, datetime
from uuid import UUID

import openai
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.rules import rules_synthesis
from app.ai.throttle import Throttle
from app.config import settings
from app.domain.suspects import SuspectsDigest
from app.models import AiSynthesis

logger = logging.getLogger("app.ai")

KIND = "suspects_weekly"

SYSTEM_PROMPT = """You summarise a food-and-symptom journal for the person who wrote it.
You receive JSON describing which ingredients were eaten in the hours before their symptom flare-ups this week.
Write one short paragraph (at most 90 words) in plain prose, in the second person.
Only cite numbers that appear in the JSON. Say plainly that these are observed associations, not proof, and that few flare windows means uncertainty.
Do not diagnose, do not tell the person to eliminate foods, and do not give medical advice."""

# Reasoning tokens are billed against this too, so it has to cover more than
# the ~90 words of prose.
MAX_TOKENS = 2000

throttle = Throttle(lambda: settings.SYNTHESIS_RATE_LIMIT_SECONDS)


def _client_factory() -> openai.AsyncOpenAI:
    """Seam for the tests: the only place the SDK client is constructed."""
    return openai.AsyncOpenAI(
        api_key=settings.OPENAI_API_KEY,
        timeout=settings.SYNTHESIS_TIMEOUT_SECONDS,
        max_retries=1,
    )


def _payload(suspects: SuspectsDigest) -> dict:
    return {
        "week": f"{suspects.week_start} to {suspects.week_end}",
        "lookbackHours": suspects.window_hours,
        "flares": suspects.flares,
        "mealsEvaluated": suspects.meals_evaluated,
        "ingredients": [
            {
                "name": item.name,
                "flareWindowsContaining": item.flares_with_ingredient,
                "flareWindowsTotal": item.flares_total,
                "averageHoursBeforeFlare": item.avg_onset_hours,
                "timesEatenThisWeek": item.times_logged_this_week,
            }
            for item in suspects.ingredients
        ],
        "timingWindows": {key: asdict(window) for key, window in suspects.timing_windows.items()},
    }


def _input_hash(suspects: SuspectsDigest) -> str:
    """Only the numbers the summary quotes, so unrelated edits don't invalidate it."""
    stable = {
        "weekStart": suspects.week_start,
        "windowHours": suspects.window_hours,
        "flares": suspects.flares,
        "mealsEvaluated": suspects.meals_evaluated,
        "ingredients": [
            [i.name, i.flares_with_ingredient, i.flares_total, i.avg_onset_hours, i.times_logged_this_week]
            for i in suspects.ingredients
        ],
        "timingWindows": {k: asdict(w) for k, w in suspects.timing_windows.items()},
    }
    return hashlib.sha256(json.dumps(stable, separators=(",", ":")).encode()).hexdigest()


async def _ask_model(suspects: SuspectsDigest) -> str | None:
    """Returns the model's paragraph, or None to fall back to the template."""
    if not settings.OPENAI_API_KEY:
        return None

    client = _client_factory()
    try:
        response = await client.responses.create(
            model=settings.SYNTHESIS_MODEL,
            max_output_tokens=MAX_TOKENS,
            # A 90-word paragraph off pre-computed numbers needs no deliberation,
            # and reasoning tokens are billed.
            reasoning={"effort": "none"},
            instructions=SYSTEM_PROMPT,
            input=json.dumps(_payload(suspects), separators=(",", ":")),
        )
    except openai.APITimeoutError:
        logger.warning("Synthesis timed out after %ss", settings.SYNTHESIS_TIMEOUT_SECONDS)
        return None
    except openai.APIConnectionError as error:
        logger.warning("Synthesis could not reach the API: %s", error)
        return None
    except openai.APIStatusError as error:
        logger.warning("Synthesis API error %s: %s", error.status_code, error.message)
        return None
    except Exception:  # never let the screen fail because of the model
        logger.exception("Synthesis failed")
        return None
    finally:
        await client.close()

    # Checked before the text is read. A refusal is a content item, not a
    # status, so it has to be looked for rather than waited on.
    if refusal := _refusal_of(response):
        logger.warning("Synthesis declined by the model (%s)", refusal)
        return None
    if response.status == "incomplete":
        reason = getattr(response.incomplete_details, "reason", None)
        logger.warning("Synthesis came back incomplete (%s); discarding it", reason or "no reason")
        return None

    return (response.output_text or "").strip() or None


def _refusal_of(response) -> str | None:
    """The refusal text, if the model declined.

    Refusals arrive as a content item inside an output message rather than as a
    top-level field, so every message's content has to be walked.
    """
    for item in getattr(response, "output", None) or []:
        if getattr(item, "type", None) != "message":
            continue
        for part in getattr(item, "content", None) or []:
            if getattr(part, "type", None) == "refusal":
                return getattr(part, "refusal", None) or "no reason given"
    return None


async def synthesize(
    session: AsyncSession, user_id: UUID, suspects: SuspectsDigest, symptom_filter: str | None
) -> dict:
    fallback = rules_synthesis(suspects)
    filter_key = symptom_filter or ""
    digest_hash = _input_hash(suspects)

    cached = await session.scalar(
        select(AiSynthesis).where(
            AiSynthesis.user_id == user_id,
            AiSynthesis.kind == KIND,
            AiSynthesis.week_start == suspects.week_start,
            AiSynthesis.symptom_filter == filter_key,
        )
    )
    # Only the model's own prose is a cache hit. A stored template is treated as
    # a miss, so the next request still tries the model: otherwise the first
    # keyless or throttled view of a week pins the template into the cache, and
    # because nothing here expires, the model is never asked again until the
    # numbers themselves change. Adding a key would then appear to do nothing.
    if cached is not None and cached.input_hash == digest_hash and cached.source == "model":
        return {
            "text": cached.text,
            "source": cached.source,
            "model": cached.model,
            "cached": True,
            "generated_at": cached.created_at,
            "suggested_watchlist": fallback.suggested_watchlist,
        }

    # A model call is only worth making when there is a key, something to
    # describe, and not more than twice a minute per person. Recording the call
    # before making it is deliberate: a fast failure should still hold the
    # window, so a broken upstream is not hammered.
    now = time.monotonic()
    text = None
    if (
        settings.OPENAI_API_KEY
        and suspects.flares > 0
        and suspects.ingredients
        and not throttle.is_throttled(user_id, now)
    ):
        throttle.record(user_id, now)
        text = await _ask_model(suspects)

    # Nothing is written unless the model wrote it. The template costs nothing
    # to regenerate, and storing it would be storing a cache miss.
    if text is None:
        return {
            "text": fallback.text,
            "source": "rules",
            "model": None,
            "cached": False,
            "generated_at": datetime.now(UTC),
            "suggested_watchlist": fallback.suggested_watchlist,
        }

    row = cached or AiSynthesis(
        user_id=user_id, kind=KIND, week_start=suspects.week_start, symptom_filter=filter_key
    )
    row.input_hash = digest_hash
    row.source = "model"
    row.model = settings.SYNTHESIS_MODEL
    row.text = text
    row.created_at = datetime.now(UTC)
    session.add(row)
    await session.commit()
    await session.refresh(row)

    return {
        "text": row.text,
        "source": "model",
        "model": row.model,
        "cached": False,
        "generated_at": row.created_at,
        "suggested_watchlist": fallback.suggested_watchlist,
    }
