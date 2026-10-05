import XCTest
@testable import TasteTraceFeatures
@testable import TasteTraceAPI
@testable import TasteTraceCore

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testSubmitGatingAndErrorMapping() async {
        let transport = StubTransport(status: 401, body: "Unauthorized")
        let session = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: InMemoryTokenStore(), transport: transport)
        let model = AuthViewModel(session: session)

        XCTAssertFalse(model.canSubmit)
        model.email = "a@b.co"; model.password = "short"
        XCTAssertFalse(model.canSubmit)
        model.password = "longenough"
        XCTAssertTrue(model.canSubmit)

        await model.submit()
        XCTAssertEqual(model.error, "Incorrect email or password.")
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/auth/bearer/login")
    }
}

final class StubTransport: Transport, @unchecked Sendable {
    let status: Int
    let body: String
    var requests: [URLRequest] = []
    init(status: Int, body: String) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class ReminderSchedulerTests: XCTestCase {
    func testCheckInsFollowTheSavedMealTimes() {
        let settings = UserSettings(breakfastTime: "07:45", lunchTime: "12:00", dinnerTime: "23:40")
        let times = ReminderScheduler.checkInTimes(for: settings)
        XCTAssertEqual(times.map { "\($0.slot) \($0.hour):\($0.minute)" }, ["breakfast 8:15", "lunch 12:30", "dinner 0:10"])
        // The defaults keep the check-in times the app used before meal times existed
        XCTAssertEqual(ReminderScheduler.checkInSummary(for: UserSettings()), "9:30 • 13:30 • 19:30")
    }

    func testSettingsSavedBeforeMealTimesStillDecode() throws {
        let json = #"{"timezone":"UTC","correlationWindowHours":24,"minTriggerCount":2,"minConfidence":50,"streakMealsPerDay":2,"nudgeTime":"20:30","nudgesEnabled":true,"mealCheckInsEnabled":false}"#
        let settings = try JSONCoding.decoder.decode(UserSettings.self, from: Data(json.utf8))
        XCTAssertEqual([settings.breakfastTime, settings.lunchTime, settings.dinnerTime], ["09:00", "13:00", "19:00"])
    }
}
