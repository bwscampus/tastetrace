import Foundation

public extension APIClient {
    func profile() async throws -> Profile {
        try await request(.get, "/api/profile")
    }

    func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        try await request(.patch, "/api/profile", body: patch)
    }

    /// The medical disclaimer onboarding must show before it can finish.
    func disclaimer() async throws -> Disclaimer {
        try await request(.get, "/api/legal/disclaimer")
    }

    func settings() async throws -> UserSettings {
        try await request(.get, "/api/settings")
    }

    func updateSettings(_ patch: SettingsPatch) async throws -> UserSettings {
        try await request(.patch, "/api/settings", body: patch)
    }
}
