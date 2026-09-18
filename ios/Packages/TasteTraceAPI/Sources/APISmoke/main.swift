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

func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    if condition() { print("  ok   \(label)") } else { failures += 1; print("  FAIL \(label)") }
}

do {
    let email = "smoke-\(Int(Date().timeIntervalSince1970))@example.com"
    let auth = try await client.register(.init(email: email, password: "pw12345", deviceName: "apismoke", firstName: "Smoke"))
    tokens.token = auth.token
    check("register returns token", auth.token.hasPrefix("tt_"))

    let me = try await client.currentUser()
    check("current user", me.email == email && me.shownName == "Smoke")

    let mealAt = Date().addingTimeInterval(-3600)
    let meal = try await client.createMeal(.init(name: "Avocado Sourdough Toast", mealType: .lunch, timestamp: mealAt, tz: tz,
                                                 ingredientDetails: [.init(name: "sourdough bread", cookMethod: "toasted"), .init(name: "avocado")]))
    check("meal ingredients mirrored", meal.ingredients == ["sourdough bread", "avocado"])
    check("meal timestamp round-trips", abs(meal.timestamp.timeIntervalSince(mealAt)) < 1)

    let created = try await client.createSymptoms(.init(timestamp: Date(), tz: tz, items: [
        .init(name: "Acid Reflux", catalogKey: "acid_reflux", intensity: 3),
        .init(name: "Bloating", catalogKey: "bloating", intensity: 1),
    ]))
    check("batch creates two symptoms", created.count == 2 && created[0].emoji == "🔥")

    let today = DayFormatter.string(from: Date(), tz: tz)
    let day = try await client.entries(on: today, tz: tz)
    check("day entries include meal + symptoms", day.meals.count >= 1 && day.symptoms.count >= 2)
    check("timeline sorted", day.timeline.map(\.timestamp) == day.timeline.map(\.timestamp).sorted())

    let markers = try await client.markers(from: Date().addingTimeInterval(-7 * 86400), to: Date().addingTimeInterval(86400), tz: tz)
    check("markers contain today", (markers[today]?.symptoms ?? 0) >= 2)

    let dish = try await client.createDish(.init(name: "Spicy tuna roll", emoji: "🍣", ingredients: [.init(name: "tuna", cookMethod: "raw"), .init(name: "rice"), .init(name: "mayo")]))
    let fromTile = try await client.logDish(id: dish.id, .init(mealType: .dinner, timestamp: Date(), tz: tz))
    check("tile log carries ingredients + dishId", fromTile.dishId == dish.id && fromTile.ingredients == ["tuna", "rice", "mayo"])
    let tiles = try await client.dishes()
    check("dish list sorted by last logged", tiles.first?.id == dish.id && tiles.first?.timesLogged == 1)
    try await client.deleteMeal(id: fromTile.id)
    try await client.deleteDish(id: dish.id)

    let catalog = try await client.symptomCatalog()
    check("catalog has 6 defaults", catalog.defaults.count == 6)

    let settings = try await client.updateSettings(.init(timezone: tz))
    check("settings timezone saved", settings.timezone == tz)

    let profile = try await client.updateProfile(.init(displayName: "Smoke Tester"))
    check("profile updated", profile.displayName == "Smoke Tester" && profile.journalerDays >= 1)

    try await client.deleteMeal(id: meal.id)
    for s in created { try await client.deleteSymptom(id: s.id) }
    try await client.revokeCurrentToken()
    do { _ = try await client.currentUser(); check("revoked token rejected", false) }
    catch APIError.unauthorized { check("revoked token rejected", true) }
} catch {
    failures += 1
    print("  FAIL threw \(error)")
}

print(failures == 0 ? "apismoke: all checks passed" : "apismoke: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

enum DayFormatter {
    static func string(from date: Date, tz: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
