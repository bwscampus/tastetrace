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

final class AccountDeletionTests: XCTestCase {
    func testDeleteAccountSendsThePasswordToDeleteMe() async throws {
        let transport = MockTransport()
        let client = APIClient(baseURL: URL(string: "https://api.example")!, transport: transport, tokenProvider: StaticTokenProvider("tt_test"))
        transport.stub("DELETE", "/api/users/me", status: 204, json: "")

        try await client.deleteAccount(password: "a pass phrase")

        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/users/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tt_test")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
        XCTAssertEqual(body?["password"], "a pass phrase")
    }
}

final class MealPhotoTests: XCTestCase {
    var transport: MockTransport!
    var client: APIClient!

    override func setUp() {
        transport = MockTransport()
        client = APIClient(baseURL: URL(string: "https://api.example")!, transport: transport, tokenProvider: StaticTokenProvider("tt_test"))
    }

    func testDecodesARecognitionIntoTheTypesTheEditorAlreadyUses() async throws {
        try transport.stub("POST", "/api/ai/meal-photo", fixture: "mealPhoto")
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00, 0x01])

        let read = try await client.recognizeMealPhoto(jpeg: jpeg, kind: .meal, mealType: .lunch, hint: "burrito")

        XCTAssertTrue(read.recognized)
        XCTAssertEqual(read.name, "Chicken burrito bowl")
        // The existing types, so this goes straight into IngredientEditor
        XCTAssertEqual(read.ingredients, [
            IngredientDetail(name: "chicken", cookMethod: "grilled"),
            IngredientDetail(name: "black beans", cookMethod: nil),
        ])
        XCTAssertEqual(read.mealCategory, .lunch)
        XCTAssertEqual(read.confidence, "high")
        XCTAssertEqual(read.model, "gpt-6-astra")
        XCTAssertNil(read.message)
        XCTAssertTrue(read.containsDairy && read.containsGrains)
    }

    func testSendsTheImageAsBase64WithTheKindAndHint() async throws {
        try transport.stub("POST", "/api/ai/meal-photo", fixture: "mealPhoto")
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x0A, 0x0B, 0x0C])

        _ = try await client.recognizeMealPhoto(jpeg: jpeg, kind: .label, mealType: nil, hint: "  pasta  ")

        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tt_test")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertEqual(body?["imageBase64"] as? String, jpeg.base64EncodedString())
        XCTAssertEqual(body?["kind"] as? String, "label")
        XCTAssertEqual(body?["hint"] as? String, "pasta", "the hint is trimmed before it is sent")
        XCTAssertNil(body?["mealType"] ?? nil)
    }

    func testAnEmptyHintIsOmittedRatherThanSentBlank() async throws {
        try transport.stub("POST", "/api/ai/meal-photo", fixture: "mealPhoto")
        _ = try await client.recognizeMealPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]), hint: "   ")

        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any]
        XCTAssertNil(body?["hint"] ?? nil)
    }

    func testAnUnreadablePhotoDecodesAsAMessageRatherThanAnError() async throws {
        transport.stub("POST", "/api/ai/meal-photo", json: #"""
        {"recognized":false,"name":"","ingredients":[],"mealCategory":null,
         "containsGluten":false,"containsDairy":false,"containsGrains":false,
         "containsSugar":false,"containsNuts":false,"confidence":"low",
         "kind":"meal","model":"gpt-6-astra",
         "message":"We couldn't read that photo. Type the meal in instead."}
        """#)

        let read = try await client.recognizeMealPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]))

        XCTAssertFalse(read.recognized)
        XCTAssertTrue(read.ingredients.isEmpty)
        XCTAssertEqual(read.message, "We couldn't read that photo. Type the meal in instead.")
        XCTAssertFalse(read.containsDairy)
    }

    func testBeingSwitchedOffSurfacesTheServersMessage() async throws {
        transport.stub("POST", "/api/ai/meal-photo", status: 503, json: #"{"detail":"Photo recognition isn't available right now. Type the meal in instead."}"#)

        do {
            _ = try await client.recognizeMealPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]))
            XCTFail("a 503 should throw so the view model can show the message")
        } catch let error as APIError {
            guard case .server(let status, let message) = error else {
                return XCTFail("expected a server error, got \(error)")
            }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(
                message,
                "Photo recognition isn't available right now. Type the meal in instead.",
                "FastAPI puts the text in `detail`; dropping it leaves only \"Request failed\""
            )
        }
    }
}

final class ServerErrorMessageTests: XCTestCase {
    private func error(status: Int, json: String) async -> APIError? {
        let transport = MockTransport()
        let client = APIClient(baseURL: URL(string: "https://api.example")!, transport: transport, tokenProvider: StaticTokenProvider("tt_test"))
        transport.stub("GET", "/api/coverage", status: status, json: json)
        do {
            _ = try await client.coverage(on: "2026-09-11", tz: "America/Los_Angeles")
            return nil
        } catch let error as APIError {
            return error
        } catch {
            return nil
        }
    }

    func testFastAPIDetailReachesTheScreen() async throws {
        let error = await self.error(status: 429, json: #"{"detail":"Give it a few seconds."}"#)
        XCTAssertEqual(error?.message, "Give it a few seconds.")
    }

    func testTheOlderMessageKeyStillWorks() async throws {
        let error = await self.error(status: 400, json: #"{"message":"Something specific."}"#)
        XCTAssertEqual(error?.message, "Something specific.")
    }

    func testAValidationErrorFallsBackRatherThanShowingFieldNoise() async throws {
        // FastAPI makes `detail` an array here, with nothing worth showing.
        let body = #"{"detail":[{"loc":["body","imageBase64"],"msg":"too long","type":"string_too_long"}]}"#
        let error = await self.error(status: 422, json: body)
        XCTAssertEqual(error?.message, "Request failed (422).")
    }
}
