export type SymptomCatalogItem = {
  key: string;
  name: string;
  emoji: string;
  bodyRegion: string;
};

// Default symptoms shown on the Quick Log grid. Mirrored in the iOS app.
export const SYMPTOM_CATALOG: SymptomCatalogItem[] = [
  { key: "acid_reflux", name: "Acid Reflux", emoji: "🔥", bodyRegion: "Upper Gastric" },
  { key: "bloating", name: "Bloating", emoji: "🎈", bodyRegion: "Abdomen" },
  { key: "abnormal_bowel", name: "Abnormal Bowel", emoji: "🚽", bodyRegion: "Lower GI Tract" },
  { key: "nausea", name: "Nausea", emoji: "🤢", bodyRegion: "Stomach" },
  { key: "skin_flare", name: "Skin Flare-ups", emoji: "🔴", bodyRegion: "Dermatological" },
  { key: "headache", name: "Headache", emoji: "🤕", bodyRegion: "Neurological" },
];

export function catalogItemByKey(key: string | null | undefined): SymptomCatalogItem | undefined {
  return SYMPTOM_CATALOG.find((item) => item.key === key);
}

export function catalogItemByName(name: string): SymptomCatalogItem | undefined {
  const lower = name.trim().toLowerCase();
  return SYMPTOM_CATALOG.find((item) => item.name.toLowerCase() === lower);
}

// Key for a user-defined symptom, e.g. "custom:brain-fog"
export function customSymptomKey(name: string): string {
  const slug = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `custom:${slug || "symptom"}`;
}
