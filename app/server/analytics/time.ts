import { formatInTimeZone, fromZonedTime } from "date-fns-tz";

export const DEFAULT_TIMEZONE = "UTC";

// True when `tz` is an IANA name the runtime knows about
export function isValidTimezone(tz: string | null | undefined): tz is string {
  if (!tz) return false;
  try {
    Intl.DateTimeFormat(undefined, { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

// Calendar day (YYYY-MM-DD) of an instant in the given timezone
export function localDate(instant: Date, tz: string): string {
  return formatInTimeZone(instant, tz, "yyyy-MM-dd");
}

// Local wall-clock time (HH:mm) of an instant in the given timezone
export function localTime(instant: Date, tz: string): string {
  return formatInTimeZone(instant, tz, "HH:mm");
}

// Start (inclusive) and end (exclusive) instants of a local calendar day
export function dayBounds(date: string, tz: string): { start: Date; end: Date } {
  const start = fromZonedTime(`${date}T00:00:00`, tz);
  const end = fromZonedTime(`${addDays(date, 1)}T00:00:00`, tz);
  return { start, end };
}

// YYYY-MM-DD arithmetic without timezone effects
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number);
  const shifted = new Date(Date.UTC(y, m - 1, d + days));
  return shifted.toISOString().slice(0, 10);
}

export function isIsoDate(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

// Parses an ISO-8601 string into a Date, or returns null when it isn't one
export function parseInstant(value: unknown): Date | null {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value !== "string") return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}
