import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// Everything the screens share: the session, API client, repositories and
/// the timezone used for day bucketing.
@Observable
@MainActor
public final class AppEnvironment {
    public let session: AuthSession
    public let entries: EntriesRepository
    public let dishes: DishRepository
    public var dateMath: DateMath

    public var api: APIClient { session.api }

    public init(session: AuthSession, dateMath: DateMath = DateMath()) {
        self.session = session
        self.entries = EntriesRepository(client: session.api)
        self.dishes = DishRepository(client: session.api)
        self.dateMath = dateMath
    }

    public static func live(baseURL: URL) -> AppEnvironment {
        AppEnvironment(session: .make(baseURL: baseURL, tokenStore: KeychainTokenStore()))
    }

    /// Reads API_BASE_URL from Info.plist (set per configuration by xcconfig).
    public static func baseURLFromBundle(default fallback: String = "http://localhost:5000") -> URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: raw?.isEmpty == false ? raw! : fallback)!
    }

    /// Runs an API call and signs out on 401 so the UI returns to sign-in.
    public func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.unauthorized {
            await session.handleUnauthorized()
            throw APIError.unauthorized
        }
    }

    /// Pushes the device timezone to the server once per launch so `date`
    /// bucketing matches what the user sees.
    public func syncTimezone() async {
        _ = try? await api.updateSettings(.init(timezone: dateMath.tzIdentifier))
    }
}
