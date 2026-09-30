import Foundation

public struct User: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let email: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var avatarEmoji: String?
    public var dataSharing: String?
    /// Nil until the first-run questions are answered.
    public var onboardingCompletedAt: Date?
    public let createdAt: Date?

    public init(id: String, email: String, firstName: String? = nil, lastName: String? = nil, displayName: String? = nil, avatarEmoji: String? = nil, dataSharing: String? = nil, onboardingCompletedAt: Date? = nil, createdAt: Date? = nil) {
        self.id = id; self.email = email; self.firstName = firstName; self.lastName = lastName
        self.displayName = displayName; self.avatarEmoji = avatarEmoji; self.dataSharing = dataSharing
        self.onboardingCompletedAt = onboardingCompletedAt; self.createdAt = createdAt
    }

    public var needsOnboarding: Bool { onboardingCompletedAt == nil }

    /// Name to show in the UI, falling back through the available fields.
    public var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
}

/// Assembled by the client: the API issues the token and the user separately.
public struct AuthResponse: Equatable, Sendable {
    public let token: String
    public let user: User

    public init(token: String, user: User) {
        self.token = token
        self.user = user
    }
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
    public var dataSharing: String?
    public var onboardingCompletedAt: Date?
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
    /// "private", "practitioner" or "research".
    public var dataSharing: String?
    /// True marks onboarding as done; the server stamps the time.
    public var onboardingCompleted: Bool?
    public init(firstName: String? = nil, lastName: String? = nil, displayName: String? = nil, avatarEmoji: String? = nil, discoveryPurpose: String? = nil, sensitivityTags: [String]? = nil, dataSharing: String? = nil, onboardingCompleted: Bool? = nil) {
        self.firstName = firstName; self.lastName = lastName; self.displayName = displayName
        self.avatarEmoji = avatarEmoji; self.discoveryPurpose = discoveryPurpose; self.sensitivityTags = sensitivityTags
        self.dataSharing = dataSharing; self.onboardingCompleted = onboardingCompleted
    }
}

