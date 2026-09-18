import Foundation

public struct Symptom: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let userId: String?
    public var name: String
    public var severity: String
    public var intensity: Int?
    public var durationMinutes: Int?
    public var catalogKey: String?
    public var timestamp: Date
    public var notes: String?
    public var date: String
    public var emoji: String?
    public var bodyRegion: String?

    /// Intensity 1-5, derived from severity for rows logged on the web.
    public var resolvedIntensity: Int {
        if let intensity { return intensity }
        switch severity {
        case "Mild": return 2
        case "Severe": return 4
        default: return 3
        }
    }
}

public struct NewSymptom: Encodable, Sendable {
    public var name: String
    public var catalogKey: String?
    public var intensity: Int
    public var timestamp: Date
    public var tz: String
    public var durationMinutes: Int?
    public var notes: String?
    public init(name: String, catalogKey: String? = nil, intensity: Int, timestamp: Date, tz: String, durationMinutes: Int? = nil, notes: String? = nil) {
        self.name = name; self.catalogKey = catalogKey; self.intensity = intensity; self.timestamp = timestamp
        self.tz = tz; self.durationMinutes = durationMinutes; self.notes = notes
    }
}

public struct SymptomBatch: Encodable, Sendable {
    public struct Item: Encodable, Sendable {
        public var name: String
        public var catalogKey: String?
        public var intensity: Int
        public init(name: String, catalogKey: String? = nil, intensity: Int) {
            self.name = name; self.catalogKey = catalogKey; self.intensity = intensity
        }
    }
    public var timestamp: Date
    public var tz: String
    public var durationMinutes: Int?
    public var notes: String?
    public var items: [Item]
    public init(timestamp: Date, tz: String, durationMinutes: Int? = nil, notes: String? = nil, items: [Item]) {
        self.timestamp = timestamp; self.tz = tz; self.durationMinutes = durationMinutes; self.notes = notes; self.items = items
    }
}

public struct SymptomPatch: Encodable, Sendable {
    public var name: String?
    public var intensity: Int?
    public var durationMinutes: Int?
    public var timestamp: Date?
    public var tz: String?
    public var notes: String?
    public init(name: String? = nil, intensity: Int? = nil, durationMinutes: Int? = nil, timestamp: Date? = nil, tz: String? = nil, notes: String? = nil) {
        self.name = name; self.intensity = intensity; self.durationMinutes = durationMinutes
        self.timestamp = timestamp; self.tz = tz; self.notes = notes
    }
}

public struct SymptomCatalogItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let key: String
    public let name: String
    public let emoji: String
    public let bodyRegion: String?
    public var id: String { key }
    public init(key: String, name: String, emoji: String, bodyRegion: String?) {
        self.key = key; self.name = name; self.emoji = emoji; self.bodyRegion = bodyRegion
    }
}

public struct CustomSymptom: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let key: String
    public let name: String
    public let emoji: String
    public let bodyRegion: String?

    public var catalogItem: SymptomCatalogItem {
        SymptomCatalogItem(key: key, name: name, emoji: emoji, bodyRegion: bodyRegion)
    }
}

public struct SymptomCatalog: Codable, Equatable, Sendable {
    public let defaults: [SymptomCatalogItem]
    public let custom: [CustomSymptom]

    public var all: [SymptomCatalogItem] { defaults + custom.map(\.catalogItem) }
}

public struct NewCustomSymptom: Encodable, Sendable {
    public var name: String
    public var emoji: String?
    public var bodyRegion: String?
    public init(name: String, emoji: String? = nil, bodyRegion: String? = nil) {
        self.name = name; self.emoji = emoji; self.bodyRegion = bodyRegion
    }
}
