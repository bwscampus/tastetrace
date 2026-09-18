import { describe, it, expect } from "vitest";
import { localDate, localTime, dayBounds, addDays, isValidTimezone, parseInstant } from "../server/analytics/time";

describe("timezone helpers", () => {
  const instant = new Date("2026-09-11T21:29:00Z"); // 2:29 PM in Los Angeles

  it("buckets an instant into the local calendar day", () => {
    expect(localDate(instant, "America/Los_Angeles")).toBe("2026-09-11");
    expect(localDate(instant, "Asia/Tokyo")).toBe("2026-09-12");
    expect(localTime(instant, "America/Los_Angeles")).toBe("14:29");
  });

  it("computes day bounds in the given timezone", () => {
    const { start, end } = dayBounds("2026-09-11", "America/Los_Angeles");
    expect(start.toISOString()).toBe("2026-09-11T07:00:00.000Z");
    expect(end.toISOString()).toBe("2026-09-12T07:00:00.000Z");
  });

  it("adds days without timezone drift", () => {
    expect(addDays("2026-02-28", 1)).toBe("2026-03-01");
    expect(addDays("2026-01-01", -1)).toBe("2025-12-31");
  });

  it("validates IANA names and parses instants", () => {
    expect(isValidTimezone("America/Los_Angeles")).toBe(true);
    expect(isValidTimezone("Mars/Olympus")).toBe(false);
    expect(parseInstant("2026-09-11T21:29:00Z")?.getTime()).toBe(instant.getTime());
    expect(parseInstant("not a date")).toBeNull();
  });
});
