import Foundation
import TasteTraceAPI

/// Mirrors app/shared/symptomCatalog.ts so the grid renders before the
/// catalog request returns.
public enum SymptomCatalogDefaults {
    public static let items: [SymptomCatalogItem] = [
        .init(key: "acid_reflux", name: "Acid Reflux", emoji: "🔥", bodyRegion: "Upper Gastric"),
        .init(key: "bloating", name: "Bloating", emoji: "🎈", bodyRegion: "Abdomen"),
        .init(key: "abnormal_bowel", name: "Abnormal Bowel", emoji: "🚽", bodyRegion: "Lower GI Tract"),
        .init(key: "nausea", name: "Nausea", emoji: "🤢", bodyRegion: "Stomach"),
        .init(key: "skin_flare", name: "Skin Flare-ups", emoji: "🔴", bodyRegion: "Dermatological"),
        .init(key: "headache", name: "Headache", emoji: "🤕", bodyRegion: "Neurological"),
    ]

    public static func item(forKey key: String?) -> SymptomCatalogItem? {
        items.first { $0.key == key }
    }

    /// Emoji for a stored symptom, falling back to the catalog by key.
    public static func emoji(for symptom: Symptom) -> String {
        symptom.emoji ?? item(forKey: symptom.catalogKey)?.emoji ?? "⚡️"
    }
}
