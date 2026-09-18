import Foundation

/// What the API returns from a sign-in: an opaque token to send as a bearer
/// credential. Its keys follow the OAuth2 convention rather than the camelCase
/// the rest of the API uses.
public struct BearerToken: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

public extension APIClient {
    struct Credentials: Encodable, Sendable {
        public var email: String
        public var password: String
        public var firstName: String?
        public var lastName: String?
        public init(email: String, password: String, firstName: String? = nil, lastName: String? = nil) {
            self.email = email; self.password = password
            self.firstName = firstName; self.lastName = lastName
        }
    }

    /// `POST /api/auth/bearer/login` — form-encoded, per the OAuth2 password flow.
    func signIn(email: String, password: String) async throws -> AuthResponse {
        let token: BearerToken = try await requestForm(
            "/api/auth/bearer/login",
            fields: ["username": email, "password": password]
        )
        let user = try await currentUser(token: token.accessToken)
        return AuthResponse(token: token.accessToken, user: user)
    }

    /// `POST /api/auth/register` — creates the account, then signs in for a token.
    func register(_ credentials: Credentials) async throws -> AuthResponse {
        let _: User = try await request(.post, "/api/auth/register", body: credentials)
        return try await signIn(email: credentials.email, password: credentials.password)
    }

    /// `GET /api/users/me` — the signed-in user, or `.unauthorized`.
    func currentUser() async throws -> User {
        try await request(.get, "/api/users/me")
    }

    /// The same, with a token that is not yet stored in the session.
    func currentUser(token: String) async throws -> User {
        let client = APIClient(baseURL: baseURL, transport: transport, tokenProvider: StaticTokenProvider(token))
        return try await client.currentUser()
    }

    /// `POST /api/auth/bearer/logout` — deletes this device's session row.
    func revokeCurrentToken() async throws {
        try await requestVoid(.post, "/api/auth/bearer/logout")
    }
}
