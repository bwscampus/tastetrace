import XCTest
@testable import TasteTraceAPI

final class APIClientTests: XCTestCase {
    var transport: MockTransport!
    var client: APIClient!

    override func setUp() {
        transport = MockTransport()
        client = APIClient(baseURL: URL(string: "https://api.example")!, transport: transport, tokenProvider: StaticTokenProvider("tt_test"))
    }

    func testDecodesDayEntriesWithBothTimestampForms() async throws {
        try transport.stub("GET", "/api/entries/date", fixture: "day")
        let day = try await client.entries(on: "2026-09-11", tz: "America/Los_Angeles")

        XCTAssertEqual(day.meals.count, 1)
        XCTAssertEqual(day.meals[0].ingredientNames, ["sourdough bread", "avocado", "salt"])
        XCTAssertEqual(day.meals[0].ingredientDetails?[0].cookMethod, "toasted")
        XCTAssertEqual(day.symptoms.count, 2)
        XCTAssertEqual(day.symptoms[0].resolvedIntensity, 3)
        XCTAssertEqual(day.symptoms[1].resolvedIntensity, 2, "Mild without intensity maps to 2")
        XCTAssertEqual(day.timeline.map(\.id), ["meal-12", "symptom-9", "symptom-10"])

        let url = transport.requests[0].url!
        XCTAssertTrue(url.query!.contains("date=2026-09-11"))
        XCTAssertTrue(url.query!.contains("tz=America/Los_Angeles"))
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer tt_test")
    }

    func testSignInSendsAFormAndDecodesTheBearerToken() async throws {
        transport.stub("POST", "/api/auth/bearer/login", json: #"{"access_token":"abc123","token_type":"bearer"}"#)
        try transport.stub("GET", "/api/users/me", fixture: "user")

        let auth = try await client.signIn(email: "taylor@example.com", password: "a pass phrase")

        XCTAssertEqual(auth.token, "abc123")
        XCTAssertEqual(auth.user.shownName, "Taylor Josephson")

        // Sign-in is the one form-encoded call, per the OAuth2 password flow
        let login = transport.requests[0]
        XCTAssertEqual(login.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(decoding: login.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("username=taylor%40example.com"), body)
        XCTAssertTrue(body.contains("password=a%20pass%20phrase"), body)

        // The token is then used to read the account
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testMarkersAndCatalog() async throws {
        try transport.stub("GET", "/api/entries/markers", fixture: "markers")
        let markers = try await client.markers(from: Date(), to: Date(), tz: "UTC")
        XCTAssertEqual(markers["2026-09-11"]?.status, "symptom")
        XCTAssertNil(markers["2026-09-12"]?.status)

        try transport.stub("GET", "/api/symptom-catalog", fixture: "catalog")
        let catalog = try await client.symptomCatalog()
        XCTAssertEqual(catalog.all.map(\.key), ["acid_reflux", "custom:brain-fog"])
    }

    func testCoverageDecodes() async throws {
        try transport.stub("GET", "/api/coverage", fixture: "coverage")
        let coverage = try await client.coverage(on: "2026-09-17", tz: "America/Los_Angeles")
        XCTAssertEqual(coverage.slots["Breakfast"]?.time, "08:15")
        XCTAssertEqual(coverage.slots["Dinner"]?.logged, false)
        XCTAssertEqual(coverage.fraction, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(coverage.streak.days, 5)
        XCTAssertEqual(coverage.weekSlots.bySlot["Lunch"]?.logged, 3)
    }

    func testErrorsMapToAPIError() async throws {
        transport.stub("GET", "/api/users/me", status: 401, json: "Unauthorized")
        do { _ = try await client.currentUser(); XCTFail("expected throw") }
        catch let error as APIError { XCTAssertEqual(error, .unauthorized) }

        transport.stub("POST", "/api/symptoms", status: 400, json: #"{"message":"Invalid symptom data"}"#)
        do {
            _ = try await client.createSymptom(.init(name: "x", intensity: 9, timestamp: Date(), tz: "UTC"))
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 400, message: "Invalid symptom data"))
        }
    }

    func testEncodesTimestampsAsISO8601() throws {
        let meal = NewMeal(name: "Tea", mealType: .snack, timestamp: Date(timeIntervalSince1970: 1_789_000_000), tz: "UTC")
        let json = String(data: try JSONCoding.encoder.encode(meal), encoding: .utf8)!
        XCTAssertTrue(json.contains(#""timestamp":"2026-09-10T"#), json)
        XCTAssertTrue(json.contains(#""mealType":"Snack""#))
    }
}
