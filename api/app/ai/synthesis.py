"""The written summary on the Food Suspect Digest.

Cached against a hash of the numbers it describes, so re-opening the screen
costs nothing and the text only changes when the data does. A model is used
when one is configured; otherwise, and on any failure, the template in
rules.py writes it instead. The endpoint never fails because of the model.
"""

import hashlib
import json
import logging
import time
from dataclasses import asdict
from datetime import UTC, datetime
from uuid import UUID

import anthropic
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.rules import rules_synthesis
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

# Thinking is on by default, so the budget has to cover it as well as ~90 words
MAX_TOKENS = 2000

_last_generated: dict[UUID, float] = {}


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


async def _ask_claude(suspects: SuspectsDigest) -> str | None:
    """Returns the model's paragraph, or None to fall back to the template."""
    if not settings.ANTHROPIC_API_KEY:
        return None

    client = anthropic.AsyncAnthropic(
        api_key=settings.ANTHROPIC_API_KEY,
        timeout=settings.SYNTHESIS_TIMEOUT_SECONDS,
        max_retries=1,
    )
    try:
        response = await client.beta.messages.create(
            model=settings.SYNTHESIS_MODEL,
            max_tokens=MAX_TOKENS,
            output_config={"effort": "low"},
            betas=["server-side-fallback-2026-06-01"],
            fallbacks=[{"model": "claude-opus-4-8"}],
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": json.dumps(_payload(suspects), separators=(",", ":"))}],
        )
    except anthropic.APITimeoutError:
        logger.warning("Synthesis timed out after %ss", settings.SYNTHESIS_TIMEOUT_SECONDS)
        return None
    except anthropic.APIConnectionError as error:
        logger.warning("Synthesis could not reach the API: %s", error)
        return None
    except anthropic.APIStatusError as error:
        logger.warning("Synthesis API error %s: %s", error.status_code, error.message)
        return None
    except Exception:  # never let the screen fail because of the model
        logger.exception("Synthesis failed")
        return None
    finally:
        await client.close()

    if response.stop_reason == "refusal":
        logger.warning("Synthesis declined by the model")
        return None
    # Thinking blocks ride along with the text ones; keep the prose
    text = "".join(block.text for block in response.content if block.type == "text").strip()
    return text or None


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
    if cached is not None and cached.input_hash == digest_hash:
        return {
            "text": cached.text,
            "source": cached.source,
            "model": cached.model,
            "cached": True,
            "generated_at": cached.created_at,
            "suggested_watchlist": fallback.suggested_watchlist,
        }

    # A model call is only worth making when there is something to describe,
    # and not more than twice a minute per person.
    now = time.monotonic()
    throttled = now - _last_generated.get(user_id, 0) < settings.SYNTHESIS_RATE_LIMIT_SECONDS
    text = None
    if suspects.flares > 0 and suspects.ingredients and not throttled:
        _last_generated[user_id] = now
        text = await _ask_claude(suspects)

    source = "claude" if text else "rules"
    row = cached or AiSynthesis(
        user_id=user_id, kind=KIND, week_start=suspects.week_start, symptom_filter=filter_key
    )
    row.input_hash = digest_hash
    row.source = source
    row.model = settings.SYNTHESIS_MODEL if text else None
    row.text = text or fallback.text
    row.created_at = datetime.now(UTC)
    session.add(row)
    await session.commit()
    await session.refresh(row)

    return {
        "text": row.text,
        "source": source,
        "model": row.model,
        "cached": False,
        "generated_at": row.created_at,
        "suggested_watchlist": fallback.suggested_watchlist,
    }
