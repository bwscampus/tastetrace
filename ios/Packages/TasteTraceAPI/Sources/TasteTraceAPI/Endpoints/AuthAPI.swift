import Foundation

public extension APIClient {
    struct Credentials: Encodable, Sendable {
        public var email: String
        public var password: String
        public var deviceName: String
        public var firstName: String?
        public var lastName: String?
        public init(email: String, password: String, deviceName: String, firstName: String? = nil, lastName: String? = nil) {
            self.email = email; self.password = password; self.deviceName = deviceName
            self.firstName = firstName; self.lastName = lastName
        }
    }

    /// `POST /api/auth/token` — exchanges email/password for a device token.
    func signIn(_ credentials: Credentials) async throws -> AuthResponse {
        try await request(.post, "/api/auth/token", body: credentials)
    }

    /// `POST /api/auth/register` — creates the account and returns a token.
    func register(_ credentials: Credentials) async throws -> AuthResponse {
        try await request(.post, "/api/auth/register", body: credentials)
    }

    /// `GET /api/user` — the signed-in user, or `.unauthorized`.
    func currentUser() async throws -> User {
        try await request(.get, "/api/user")
    }

    /// `DELETE /api/auth/token` — revokes the token in use (sign out).
    func revokeCurrentToken() async throws {
        try await requestVoid(.delete, "/api/auth/token")
    }

    func listTokens() async throws -> [ApiTokenInfo] {
        try await request(.get, "/api/auth/tokens")
    }

    func revokeToken(id: Int) async throws {
        try await requestVoid(.delete, "/api/auth/tokens/\(id)")
    }
}
