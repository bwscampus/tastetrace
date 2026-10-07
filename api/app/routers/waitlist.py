"""The landing page's signup form.

The only unauthenticated write in this API, and the only route that answers a
browser, so it carries its own CORS rather than switching on the shared
middleware: that one applies to every route with credentials enabled, which is
far more than one public form needs.

Ported from the Express backend being retired, keeping its behaviour intact —
the honeypot, the idempotent insert, and the single reply.
"""

import logging

from fastapi import APIRouter, Request, Response, status
from sqlalchemy.exc import IntegrityError

from app.config import settings
from app.deps import Session
from app.models import WaitlistSignup
from app.schemas import WaitlistRead, WaitlistRequest

logger = logging.getLogger("app.waitlist")

router = APIRouter(tags=["waitlist"])

# One reply whether the address is new, already on the list, or a bot's. Saying
# "you're already on it" would turn this into a way to test whether a given
# address had signed up.
JOINED = "You're on the list"


def _allow_origin(request: Request, response: Response) -> None:
    origin = request.headers.get("origin")
    if origin and origin in settings.WAITLIST_ORIGINS:
        response.headers["Access-Control-Allow-Origin"] = origin
        # Vary matters: without it a cache could serve one origin's response
        # to another.
        response.headers["Vary"] = "Origin"
        response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type"


@router.options("/waitlist", include_in_schema=False)
async def waitlist_preflight(request: Request, response: Response) -> Response:
    _allow_origin(request, response)
    response.status_code = status.HTTP_204_NO_CONTENT
    return response


@router.post("/waitlist", response_model=WaitlistRead, status_code=status.HTTP_201_CREATED)
async def join_waitlist(
    body: WaitlistRequest, request: Request, response: Response, session: Session
) -> dict:
    _allow_origin(request, response)

    # A real visitor never sees this field, so anything in it is a bot. Answer
    # exactly as if it worked, and store nothing.
    if body.company:
        logger.info("Waitlist honeypot tripped")
        return {"message": JOINED}

    # A repeat signup is a no-op, not an error, which is what lets the reply
    # above stay the same every time. Catching the constraint rather than
    # checking first keeps it correct under a race, and works on both Postgres
    # and the SQLite the tests run on.
    session.add(WaitlistSignup(email=body.email))
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        logger.info("Waitlist signup was already on the list")
        return {"message": JOINED}
    # The address itself is never logged: it is personal data and this is the
    # one route anyone on the internet can reach.
    logger.info("Waitlist signup accepted")
    return {"message": JOINED}
