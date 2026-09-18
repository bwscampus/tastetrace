import Foundation
import TasteTraceAPI

// Runs the real client against a backend: `swift run apismoke http://localhost:5000`
// Registers a throwaway user, logs a meal and a symptom, reads them back.
let base = CommandLine.arguments.dropFirst().first ?? "http://localhost:5000"
guard let baseURL = URL(string: base) else { fatalError("Bad URL \(base)") }

final class Box: TokenProvider, @unchecked Sendable {
    var token: String?
    func currentToken() async -> String? { token }
}

let tokens = Box()
let client = APIClient(baseURL: baseURL, tokenProvider: tokens)
let tz = TimeZone.current.identifier
var failures = 0

// Everything is anchored to a fixed hour of the previous local day, so the
// run never straddles local midnight: a meal "an hour ago" can otherwise
// belong to a different local day than the symptom that follows it.
let anchorDay = DayFormatter.string(from: Date().addingTimeInterval(-86400), tz: tz)
let mealAt = DayFormatter.instant(day: anchorDay, hour: 12, minute: 45, tz: tz)
let flareAt = DayFormatter.instant(day: anchorDay, hour: 14, minute: 29, tz: tz)

func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    if condition() { print("  ok   \(label)") } else { failures += 1; print("  FAIL \(label)") }
}

do {
    let email = "smoke-\(Int(Date().timeIntervalSince1970))@example.com"
    let auth = try await client.register(.init(email: email, password: "correct horse battery", firstName: "Smoke"))
    tokens.token = auth.token
    check("register returns a token", !auth.token.isEmpty)

    let me = try await client.currentUser()
    check("current user", me.email == email && me.shownName == "Smoke")

    let meal = try await client.createMeal(.init(name: "Avocado Sourdough Toast", mealType: .lunch, timestamp: mealAt, tz: tz,
                                                 ingredientDetails: [.init(name: "sourdough bread", cookMethod: "toasted"), .init(name: "avocado")]))
    check("meal ingredients mirrored", meal.ingredients == ["sourdough bread", "avocado"])
    check("meal timestamp round-trips", abs(meal.timestamp.timeIntervalSince(mealAt)) < 1)

    let created = try await client.createSymptoms(.init(timestamp: flareAt, tz: tz, items: [
        .init(name: "Acid Reflux", catalogKey: "acid_reflux", intensity: 3),
        .init(name: "Bloating", catalogKey: "bloating", intensity: 1),
    ]))
    check("batch creates two symptoms", created.count == 2 && created[0].emoji == "🔥")

    let day = try await client.entries(on: anchorDay, tz: tz)
    check("day entries include meal + symptoms", day.meals.count >= 1 && day.symptoms.count >= 2)
    check("timeline sorted", day.timeline.map(\.timestamp) == day.timeline.map(\.timestamp).sorted())

    let markers = try await client.markers(from: Date().addingTimeInterval(-7 * 86400), to: Date().addingTimeInterval(86400), tz: tz)
    check("markers mark the logged day", (markers[anchorDay]?.symptoms ?? 0) >= 2)

    let dish = try await client.createDish(.init(name: "Spicy tuna roll", emoji: "🍣", ingredients: [.init(name: "tuna", cookMethod: "raw"), .init(name: "rice"), .init(name: "mayo")]))
    let fromTile = try await client.logDish(id: dish.id, .init(mealType: .dinner, timestamp: flareAt, tz: tz))
    check("tile log carries ingredients + dishId", fromTile.dishId == dish.id && fromTile.ingredients == ["tuna", "rice", "mayo"])
    let tiles = try await client.dishes()
    check("dish list sorted by last logged", tiles.first?.id == dish.id && tiles.first?.timesLogged == 1)
    try await client.deleteMeal(id: fromTile.id)
    try await client.deleteDish(id: dish.id)

    let coverage = try await client.coverage(on: anchorDay, tz: tz)
    check("coverage counts the logged lunch", coverage.slots["Lunch"]?.logged == true && coverage.week.count == 7 && coverage.slotTotal == 3)

    let weekStart = DayFormatter.string(from: Date().addingTimeInterval(-7 * 86400), tz: tz)
    let digest = try await client.weeklyDigest(weekStart: weekStart, tz: tz)
    check("weekly digest covers 7 days with today's symptoms", digest.trends.days.count == 7 && digest.symptoms.total >= 2 && digest.symptoms.cards.first?.emoji != nil)
    let suspectsDigest = try await client.suspects(weekStart: weekStart, symptom: nil, tz: tz)
    check("suspects sees the flare and the toast", suspectsDigest.flares >= 1 && suspectsDigest.leadSuspect != nil && suspectsDigest.symptomFilters.first?.name == "All Symptoms")
    let insights = try await client.triggerInsights(dimension: "ingredient", symptom: nil, minConfidence: 0)
    check("trigger insights list symptoms and cards", insights.symptoms.count >= 2 && insights.cards.contains { $0.item == "sourdough bread" })
    let watched = try await client.addToWatchlist("Sourdough Bread", source: "suspect")
    let watchlist = try await client.watchlist()
    check("watchlist normalises and reports confidence", watched.ingredient == "sourdough bread" && watchlist.first?.confidenceMax != nil)
    try await client.removeFromWatchlist(id: watched.id)
    let flagged = try await client.entries(on: anchorDay, tz: tz)
    check("meal is flagged suspicious", flagged.meals.first?.suspiciousFor?.isEmpty == false)

    let synthesis = try await client.synthesis(weekStart: weekStart, symptom: nil, tz: tz)
    check("synthesis returns text (\(synthesis.source))", synthesis.text.count > 20 && ["claude", "rules"].contains(synthesis.source))
    let again = try await client.synthesis(weekStart: weekStart, symptom: nil, tz: tz)
    check("synthesis is cached on repeat", again.cached && again.text == synthesis.text)

    let today = DayFormatter.string(from: Date(), tz: tz)
    let csv = String(decoding: try await client.csvExport(from: weekStart, to: today, tz: tz), as: UTF8.self)
    check("csv export has header and rows", csv.hasPrefix("entry_type,id,date,time,name") && csv.contains("Avocado Sourdough Toast"))
    let ledger = try await client.ledger(from: weekStart, to: today, tz: tz)
    check("ledger bundle decodes", ledger.range.tz == tz && ledger.days.count >= 1 && ledger.digestWeeks.count >= 1 && ledger.shownName == "Smoke Tester" || ledger.shownName == "Smoke")

    let catalog = try await client.symptomCatalog()
    check("catalog has 6 defaults", catalog.defaults.count == 6)

    let settings = try await client.updateSettings(.init(timezone: tz))
    check("settings timezone saved", settings.timezone == tz)

    let profile = try await client.updateProfile(.init(displayName: "Smoke Tester"))
    check("profile updated", profile.displayName == "Smoke Tester" && profile.journalerDays >= 1)

    try await client.deleteMeal(id: meal.id)
    for s in created { try await client.deleteSymptom(id: s.id) }
    try await client.revokeCurrentToken()
    do { _ = try await client.currentUser(); check("signing out rejects the token", false) }
    catch APIError.unauthorized { check("signing out rejects the token", true) }
} catch {
    failures += 1
    print("  FAIL threw \(error)")
}

print(failures == 0 ? "apismoke: all checks passed" : "apismoke: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

enum DayFormatter {
    static func string(from date: Date, tz: String) -> String {
        formatter(tz: tz, format: "yyyy-MM-dd").string(from: date)
    }

    /// A precise local wall-clock time on a given day.
    static func instant(day: String, hour: Int, minute: Int, tz: String) -> Date {
        let stamp = String(format: "%@ %02d:%02d", day, hour, minute)
        return formatter(tz: tz, format: "yyyy-MM-dd HH:mm").date(from: stamp)!
    }

    private static func formatter(tz: String, format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = format
        return f
    }
}
