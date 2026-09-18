"""The two symptom scales.

The app records intensity 1-5; the wording (Mild/Moderate/Severe) is what the
web app and the exports use. Both are always stored, each derived from the
other when missing.
"""

MILD = "Mild"
MODERATE = "Moderate"
SEVERE = "Severe"


def severity_from_intensity(intensity: int) -> str:
    if intensity <= 2:
        return MILD
    if intensity == 3:
        return MODERATE
    return SEVERE


def intensity_from_severity(severity: str) -> int:
    if severity == MILD:
        return 2
    if severity == SEVERE:
        return 4
    return 3


def discomfort_score(intensity: int) -> float:
    """The 0-10 scale the digests report."""
    return intensity * 2


def severity_fields(severity: str | None, intensity: int | None) -> tuple[str, int]:
    """Fills in whichever level is missing."""
    if intensity is not None:
        return severity or severity_from_intensity(intensity), intensity
    resolved = severity or MODERATE
    return resolved, intensity_from_severity(resolved)
