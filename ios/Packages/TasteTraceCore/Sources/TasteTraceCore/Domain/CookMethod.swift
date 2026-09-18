import Foundation

/// Mirrors app/shared/cookMethods.ts.
public enum CookMethod: String, CaseIterable, Identifiable, Sendable {
    case raw, grilled, fried, deepFried = "deep_fried", baked, roasted, boiled, steamed, sauteed, smoked, fermented, processed, toasted

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .deepFried: return "Deep fried"
        case .sauteed: return "Sautéed"
        default: return rawValue.capitalized
        }
    }

    public static func label(for raw: String?) -> String? {
        guard let raw else { return nil }
        return CookMethod(rawValue: raw)?.label ?? raw.capitalized
    }
}

/// Parses "avocado, sourdough bread, salt" into trimmed, de-duplicated names.
public func parseIngredientInput(_ text: String, existing: [String] = []) -> [String] {
    var seen = Set(existing.map { $0.lowercased() })
    var result: [String] = []
    for raw in text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" }) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !seen.contains(name.lowercased()) else { continue }
        seen.insert(name.lowercased())
        result.append(name)
    }
    return result
}
