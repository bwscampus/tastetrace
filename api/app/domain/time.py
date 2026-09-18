"""Local-day arithmetic.

Entries are bucketed into the user's local calendar day, so every conversion
goes through an explicit IANA zone. Timestamps are timezone-aware UTC
everywhere else.
"""

from datetime import date as date_cls
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

ISO_DAY = "%Y-%m-%d"


def as_utc(value: datetime) -> datetime:
    """SQLite returns naive datetimes; treat those as UTC."""
    return value.replace(tzinfo=ZoneInfo("UTC")) if value.tzinfo is None else value


def local_date(instant: datetime, tz: str) -> str:
    """The YYYY-MM-DD the instant falls on in `tz`."""
    return as_utc(instant).astimezone(ZoneInfo(tz)).strftime(ISO_DAY)


def local_time(instant: datetime, tz: str) -> str:
    """24-hour HH:mm in `tz`."""
    return as_utc(instant).astimezone(ZoneInfo(tz)).strftime("%H:%M")


def day_bounds(day: str, tz: str) -> tuple[datetime, datetime]:
    """Start (inclusive) and end (exclusive) instants of a local day."""
    zone = ZoneInfo(tz)
    start = datetime.fromisoformat(f"{day}T00:00:00").replace(tzinfo=zone)
    end = datetime.fromisoformat(f"{add_days(day, 1)}T00:00:00").replace(tzinfo=zone)
    return start.astimezone(ZoneInfo("UTC")), end.astimezone(ZoneInfo("UTC"))


def add_days(day: str, days: int) -> str:
    """Pure date arithmetic on YYYY-MM-DD; no DST effects."""
    return (date_cls.fromisoformat(day) + timedelta(days=days)).strftime(ISO_DAY)


def days_between(start: str, end: str) -> int:
    return (date_cls.fromisoformat(end) - date_cls.fromisoformat(start)).days


def is_iso_day(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        date_cls.fromisoformat(value)
    except ValueError:
        return False
    return len(value) == 10


def parse_instant_or_none(value: object) -> datetime | None:
    """Parses an ISO-8601 instant, tolerating a trailing Z; None if it isn't one."""
    if isinstance(value, datetime):
        return as_utc(value)
    if not isinstance(value, str):
        return None
    try:
        return as_utc(datetime.fromisoformat(value.replace("Z", "+00:00")))
    except ValueError:
        return None


def weekday_label(day: str) -> str:
    """Short weekday name ("Fri") for a YYYY-MM-DD."""
    return date_cls.fromisoformat(day).strftime("%a")


def week_dates(week_start: str) -> list[str]:
    return [add_days(week_start, i) for i in range(7)]
