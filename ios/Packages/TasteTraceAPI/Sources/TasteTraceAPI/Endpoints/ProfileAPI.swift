import Foundation

public extension APIClient {
    func profile() async throws -> Profile {
        try await request(.get, "/api/profile")
    }

    func updateProfile(_ patch: ProfilePatch) async throws -> Profile {
        try await request(.patch, "/api/profile", body: patch)
    }

    func settings() async throws -> Settings {
        try await request(.get, "/api/settings")
    }

    func updateSettings(_ patch: SettingsPatch) async throws -> Settings {
        try await request(.patch, "/api/settings", body: patch)
    }
}
