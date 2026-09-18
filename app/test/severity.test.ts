import { describe, it, expect } from "vitest";
import { severityFromIntensity, intensityFromSeverity, discomfortScore } from "../shared/severity";
import { customSymptomKey, catalogItemByName } from "../shared/symptomCatalog";

describe("severity <-> intensity", () => {
  it("maps intensity to the web severity levels", () => {
    expect(severityFromIntensity(1)).toBe("Mild");
    expect(severityFromIntensity(2)).toBe("Mild");
    expect(severityFromIntensity(3)).toBe("Moderate");
    expect(severityFromIntensity(4)).toBe("Severe");
    expect(severityFromIntensity(5)).toBe("Severe");
  });

  it("maps severity to a representative intensity and back", () => {
    for (const severity of ["Mild", "Moderate", "Severe"]) {
      expect(severityFromIntensity(intensityFromSeverity(severity))).toBe(severity);
    }
  });

  it("scores discomfort on a 10-point scale (mockup: level 3 = 6.0)", () => {
    expect(discomfortScore(3)).toBe(6);
  });
});

describe("symptom catalog", () => {
  it("finds default symptoms by name, case-insensitively", () => {
    expect(catalogItemByName("acid reflux")?.key).toBe("acid_reflux");
    expect(catalogItemByName("Brain fog")).toBeUndefined();
  });

  it("derives stable custom keys", () => {
    expect(customSymptomKey(" Brain Fog! ")).toBe("custom:brain-fog");
    expect(customSymptomKey("???")).toBe("custom:symptom");
  });
});
