import XCTest
@testable import TasteTraceCore
import TasteTraceAPI

final class DateMathTests: XCTestCase {
    let math = DateMath(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func testDayStringUsesTheGivenZone() {
        let instant = Date(timeIntervalSince1970: 1_789_680_983) // 2026-09-17 21:36 UTC
        XCTAssertEqual(math.dayString(instant), "2026-09-17")
        XCTAssertEqual(DateMath(timeZone: TimeZone(identifier: "Asia/Tokyo")!).dayString(instant), "2026-09-18")
    }

    func testWeekStartsOnMonday() {
        let thursday = math.date(fromDay: "2026-09-17")!
        let week = math.week(containing: thursday).map(math.dayString)
        XCTAssertEqual(week.first, "2026-09-14")
        XCTAssertEqual(week.last, "2026-09-20")
        XCTAssertEqual(math.trailingWeek(endingOn: thursday).map(math.dayString).first, "2026-09-11")
    }

    func testCombineDayAndTime() {
        let day = math.date(fromDay: "2026-09-11")!
        let time = math.calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12, minute: 45))!
        XCTAssertEqual(math.dayString(math.combine(day: day, time: time)), "2026-09-11")
        XCTAssertEqual(math.calendar.component(.hour, from: math.combine(day: day, time: time)), 12)
    }
}

final class SeverityMappingTests: XCTestCase {
    func testRoundTrip() {
        for severity in ["Mild", "Moderate", "Severe"] {
            XCTAssertEqual(SeverityMapping.severity(forIntensity: SeverityMapping.intensity(forSeverity: severity)), severity)
        }
        XCTAssertEqual(SeverityMapping.discomfortScore(intensity: 3), 6)
    }
}

final class JSONFileStoreTests: XCTestCase {
    func testSaveLoadClear() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = JSONFileStore<UserSettings>(name: "settings", directory: dir)
        XCTAssertNil(store.load())
        try store.save(UserSettings(timezone: "America/Los_Angeles"))
        XCTAssertEqual(store.load()?.timezone, "America/Los_Angeles")
        store.clear()
        XCTAssertNil(store.load())
    }
}

final class IngredientParsingTests: XCTestCase {
    func testSplitsTrimsAndDedupes() {
        XCTAssertEqual(parseIngredientInput(" avocado, Sourdough bread ,salt,, avocado"), ["avocado", "Sourdough bread", "salt"])
        XCTAssertEqual(parseIngredientInput("salt", existing: ["Salt"]), [])
        XCTAssertEqual(CookMethod.label(for: "deep_fried"), "Deep fried")
        XCTAssertEqual(CookMethod.label(for: nil), nil)
    }
}

final class WatchlistMatchTests: XCTestCase {
    func testSubstringCaseInsensitiveMatch() {
        XCTAssertEqual(watchlistMatches(watchlist: ["sourdough bread", "dairy"], ingredients: ["Sourdough Bread", "avocado"]), ["sourdough bread"])
        XCTAssertEqual(watchlistMatches(watchlist: ["milk"], ingredients: ["oat milk"]), ["milk"])
        XCTAssertEqual(watchlistMatches(watchlist: [], ingredients: ["salt"]), [])
    }
}

/// Answers every request with one canned status and body.
final class CannedTransport: Transport, @unchecked Sendable {
    let status: Int
    let body: String
    init(status: Int, body: String = "") { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class SignOutHygieneTests: XCTestCase {
    private func cacheWithJournal() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try JSONFileStore<UserSettings>(name: "day-2026-09-11", directory: dir).save(UserSettings(timezone: "UTC"))
        return dir
    }

    @MainActor
    func testSignOutRemovesTokenAndCachedJournal() async throws {
        let dir = try cacheWithJournal()
        let tokens = InMemoryTokenStore("tt_old")
        let session = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: tokens, transport: CannedTransport(status: 204), cacheDirectory: dir)

        await session.signOut()

        XCTAssertNil(tokens.load())
        XCTAssertEqual(session.state, .signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "cached entries must not survive sign-out")
    }

    @MainActor
    func testDeleteAccountClearsEverythingOnlyWhenTheServerAgrees() async throws {
        let dir = try cacheWithJournal()
        let tokens = InMemoryTokenStore("tt_old")
        let refused = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: tokens, transport: CannedTransport(status: 400, body: #"{"detail":"bad password"}"#), cacheDirectory: dir)

        do {
            try await refused.deleteAccount(password: "wrong")
            XCTFail("a refused deletion must throw")
        } catch {}
        XCTAssertEqual(tokens.load(), "tt_old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        let accepted = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: tokens, transport: CannedTransport(status: 204), cacheDirectory: dir)
        try await accepted.deleteAccount(password: "right")
        XCTAssertNil(tokens.load())
        XCTAssertEqual(accepted.state, .signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
