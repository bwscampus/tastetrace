import Foundation

public struct User: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var avatarEmoji: String?
    public let createdAt: Date?

    public init(id: String, email: String, firstName: String? = nil, lastName: String? = nil, displayName: String? = nil, avatarEmoji: String? = nil, createdAt: Date? = nil) {
        self.id = id; self.email = email; self.firstName = firstName; self.lastName = lastName
        self.displayName = displayName; self.avatarEmoji = avatarEmoji; self.createdAt = createdAt
    }

    /// Name to show in the UI, falling back through the available fields.
    public var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
}

public struct AuthResponse: Codable, Equatable, Sendable {
    public let token: String
    public let user: User
}

public struct Profile: Codable, Equatable, Sendable {
    public let id: String
    public let email: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var avatarEmoji: String?
    public var discoveryPurpose: String?
    public var sensitivityTags: [String]
    public let createdAt: Date?
    public let journalerDays: Int
    public let firstLogAt: Date?
}

public struct ProfilePatch: Encodable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var avatarEmoji: String?
    public var discoveryPurpose: String?
    public var sensitivityTags: [String]?
    public init(firstName: String? = nil, lastName: String? = nil, displayName: String? = nil, avatarEmoji: String? = nil, discoveryPurpose: String? = nil, sensitivityTags: [String]? = nil) {
        self.firstName = firstName; self.lastName = lastName; self.displayName = displayName
        self.avatarEmoji = avatarEmoji; self.discoveryPurpose = discoveryPurpose; self.sensitivityTags = sensitivityTags
    }
}

public struct ApiTokenInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let deviceName: String?
    public let createdAt: Date?
    public let lastUsedAt: Date?
    public let current: Bool
}
