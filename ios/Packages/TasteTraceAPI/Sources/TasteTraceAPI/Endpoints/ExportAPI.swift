import Foundation

/// `GET /api/export/ledger` — everything the on-device PDF reports render.
public struct LedgerBundle: Codable, Sendable {
    public struct ProfileInfo: Codable, Sendable {
        public let id: String
        public let email: String
        public let firstName: String?
        public let lastName: String?
        public let displayName: String?
        public let discoveryPurpose: String?
        public let sensitivityTags: [String]
    }

    public struct Range: Codable, Sendable {
        public let from: String
        public let to: String
        public let tz: String
    }

    public struct Totals: Codable, Sendable {
        public let meals: Int
        public let symptoms: Int
        public let days: Int
    }

    public struct Day: Codable, Sendable {
        public let date: String
        public let meals: [Meal]
        public let symptoms: [Symptom]
        public let flares: Int
    }

    public struct Trigger: Codable, Sendable {
        public let foodName: String
        public let symptomName: String
        public let dimension: String
        public let confidence: Int
        public let tier: String
        public let exposures: Int
        public let flareExposures: Int
        public let avgOnsetHours: Double?
    }

    public let generatedAt: Date
    public let profile: ProfileInfo?
    public let settings: UserSettings
    public let range: Range
    public let totals: Totals
    public let days: [Day]
    public let triggers: [Trigger]
    public let digestWeeks: [WeeklyDigest]

    public var shownName: String {
        guard let profile else { return "TasteTrace user" }
        if let name = profile.displayName, !name.isEmpty { return name }
        let full = [profile.firstName, profile.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? profile.email : full
    }
}

public extension APIClient {
    func ledger(from: String, to: String, tz: String) async throws -> LedgerBundle {
        try await request(.get, "/api/export/ledger", query: ["from": from, "to": to, "tz": tz])
    }

    /// Raw CSV bytes for the range.
    func csvExport(from: String, to: String, tz: String) async throws -> Data {
        try await requestData(.get, "/api/export/csv", query: ["from": from, "to": to, "tz": tz])
    }
}
