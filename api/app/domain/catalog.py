"""The built-in symptom grid, mirrored in the iOS app."""

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class CatalogEntry:
    key: str
    name: str
    emoji: str
    body_region: str


SYMPTOM_CATALOG: tuple[CatalogEntry, ...] = (
    CatalogEntry("acid_reflux", "Acid Reflux", "🔥", "Upper Gastric"),
    CatalogEntry("bloating", "Bloating", "🎈", "Abdomen"),
    CatalogEntry("abnormal_bowel", "Abnormal Bowel", "🚽", "Lower GI Tract"),
    CatalogEntry("nausea", "Nausea", "🤢", "Stomach"),
    CatalogEntry("skin_flare", "Skin Flare-ups", "🔴", "Dermatological"),
    CatalogEntry("headache", "Headache", "🤕", "Neurological"),
)


def catalog_by_key(key: str | None) -> CatalogEntry | None:
    return next((item for item in SYMPTOM_CATALOG if item.key == key), None)


def catalog_by_name(name: str) -> CatalogEntry | None:
    lowered = name.strip().lower()
    return next((item for item in SYMPTOM_CATALOG if item.name.lower() == lowered), None)


def custom_symptom_key(name: str) -> str:
    """Stable key for a user-defined symptom, e.g. "custom:brain-fog"."""
    slug = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return f"custom:{slug or 'symptom'}"
