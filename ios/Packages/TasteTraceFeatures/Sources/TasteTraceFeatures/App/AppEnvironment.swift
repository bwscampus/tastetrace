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
    public let watchlist: WatchlistStore
    public let reminders: ReminderScheduler
    public var dateMath: DateMath

    public var api: APIClient { session.api }

    public init(session: AuthSession, dateMath: DateMath = DateMath()) {
        self.session = session
        self.entries = EntriesRepository(client: session.api)
        self.dishes = DishRepository(client: session.api)
        self.watchlist = WatchlistStore()
        self.reminders = ReminderScheduler()
        self.dateMath = dateMath
        // Sign-out, account deletion and 401 all end here: stop the reminders
        // and drop the in-memory watchlist along with the cached files.
        session.onSessionEnded = { [reminders, watchlist] in
            reminders.cancelAll()
            await watchlist.reset()
        }
    }

    public static func live(baseURL: URL) -> AppEnvironment {
        AppEnvironment(session: .make(baseURL: baseURL, tokenStore: KeychainTokenStore()))
    }

    /// Reads API_BASE_URL from Info.plist (set per configuration by xcconfig).
    /// A missing or malformed value is a build misconfiguration: fail loudly in
    /// Debug, and in Release return an address that can never connect rather
    /// than silently talking to an old local server over plain HTTP (FE-7).
    public static func baseURLFromBundle(bundle: Bundle = .main) -> URL {
        let raw = (bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespaces)
        if let raw, !raw.isEmpty, let url = URL(string: raw), url.scheme != nil, url.host != nil {
            return url
        }
        assertionFailure("API_BASE_URL is missing or invalid in Info.plist; set it in ios/Config/*.xcconfig")
        return URL(string: "https://api-base-url-not-configured.invalid")!
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

    /// Refreshes the cached watchlist and re-schedules reminders from saved settings.
    public func syncPreferences() async {
        if let items = try? await api.watchlist() { await watchlist.replace(items) }
        if let settings = try? await api.settings() { await reminders.sync(settings: settings, math: dateMath) }
    }
}
