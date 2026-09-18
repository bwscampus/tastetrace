import Foundation
import Observation
import TasteTraceAPI

/// Signed-in state for the whole app. Owns the token and the current user.
@Observable
@MainActor
public final class AuthSession {
    public enum State: Equatable {
        case unknown          // launching; token not yet validated
        case signedOut
        case signedIn(User)
    }

    public private(set) var state: State = .unknown
    public var lastError: String?

    private let client: APIClient
    private let tokenStore: TokenStore
    private let tokenBox: TokenBox

    /// Builds the session and the client it authenticates.
    public static func make(baseURL: URL, tokenStore: TokenStore, transport: Transport = URLSessionTransport()) -> AuthSession {
        let box = TokenBox(tokenStore.load())
        let client = APIClient(baseURL: baseURL, transport: transport, tokenProvider: box)
        return AuthSession(client: client, tokenStore: tokenStore, tokenBox: box)
    }

    init(client: APIClient, tokenStore: TokenStore, tokenBox: TokenBox) {
        self.client = client
        self.tokenStore = tokenStore
        self.tokenBox = tokenBox
    }

    public var api: APIClient { client }

    public var user: User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    /// Validates a stored token on launch.
    public func restore() async {
        guard tokenBox.token != nil else { state = .signedOut; return }
        do {
            state = .signedIn(try await client.currentUser())
        } catch APIError.unauthorized {
            await clearToken()
            state = .signedOut
        } catch {
            // Offline: keep the token and let the UI show cached data
            if let cached = CachedUser.load() { state = .signedIn(cached) } else { state = .signedOut }
        }
    }

    public func signIn(email: String, password: String) async throws {
        let auth = try await client.signIn(.init(email: email, password: password, deviceName: Self.deviceName))
        try adopt(auth)
    }

    public func register(email: String, password: String, firstName: String?, lastName: String?) async throws {
        let auth = try await client.register(.init(email: email, password: password, deviceName: Self.deviceName, firstName: firstName, lastName: lastName))
        try adopt(auth)
    }

    public func signOut() async {
        try? await client.revokeCurrentToken()
        await clearToken()
        state = .signedOut
    }

    /// Called when any request comes back 401.
    public func handleUnauthorized() async {
        await clearToken()
        state = .signedOut
    }

    public func refreshUser() async {
        if let user = try? await client.currentUser() {
            state = .signedIn(user)
            CachedUser.save(user)
        }
    }

    private func adopt(_ auth: AuthResponse) throws {
        try tokenStore.save(auth.token)
        tokenBox.token = auth.token
        CachedUser.save(auth.user)
        state = .signedIn(auth.user)
    }

    private func clearToken() async {
        tokenStore.clear()
        tokenBox.token = nil
        CachedUser.clear()
    }

    static var deviceName: String {
        #if os(iOS)
        return "iPhone"
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
}

/// Mutable token handed to the API client.
final class TokenBox: TokenProvider, @unchecked Sendable {
    var token: String?
    init(_ token: String?) { self.token = token }
    func currentToken() async -> String? { token }
}

enum CachedUser {
    static let store = JSONFileStore<User>(name: "user")
    static func load() -> User? { store.load() }
    static func save(_ user: User) { try? store.save(user) }
    static func clear() { store.clear() }
}
