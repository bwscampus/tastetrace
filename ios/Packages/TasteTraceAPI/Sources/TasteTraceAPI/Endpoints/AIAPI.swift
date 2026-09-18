import Foundation

/// `POST /api/ai/synthesis`
public struct Synthesis: Codable, Equatable, Sendable {
    public let text: String
    public let source: String // claude | rules
    public let model: String?
    public let cached: Bool
    public let generatedAt: Date?
    public let suggestedWatchlist: [String]
}

public extension APIClient {
    func synthesis(weekStart: String, symptom: String?, tz: String) async throws -> Synthesis {
        struct Body: Encodable { let weekStart: String; let symptom: String?; let tz: String }
        return try await request(.post, "/api/ai/synthesis", body: Body(weekStart: weekStart, symptom: symptom, tz: tz))
    }
}
