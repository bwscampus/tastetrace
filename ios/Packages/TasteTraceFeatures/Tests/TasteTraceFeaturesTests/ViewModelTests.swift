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

final class MealPhotoRecognitionTests: XCTestCase {
    @MainActor
    private func model() -> LogMealViewModel {
        let session = AuthSession.make(
            baseURL: URL(string: "https://api.example")!,
            tokenStore: InMemoryTokenStore(),
            transport: StubTransport(status: 200, body: "{}")
        )
        return LogMealViewModel(env: AppEnvironment(session: session), date: Date())
    }

    private func read(
        recognized: Bool = true,
        name: String = "Chicken burrito bowl",
        ingredients: [IngredientDetail] = [IngredientDetail(name: "chicken", cookMethod: "grilled")],
        mealCategory: MealType? = .lunch,
        confidence: String = "high",
        message: String? = nil,
        gluten: Bool = false,
        dairy: Bool = true,
        grains: Bool = true
    ) -> MealPhotoRecognition {
        MealPhotoRecognition(
            recognized: recognized, name: name, ingredients: ingredients,
            mealCategory: mealCategory, containsGluten: gluten, containsDairy: dairy,
            containsGrains: grains, containsSugar: false, containsNuts: false,
            confidence: confidence, kind: "meal", model: "gpt-6-astra", message: message
        )
    }

    @MainActor
    func testARecognitionPreFillsAFoodAndGoesToTheEditorRatherThanLogging() {
        let model = model()
        model.apply(read())

        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.items[0].name, "Chicken burrito bowl")
        XCTAssertEqual(model.items[0].ingredients, [IngredientDetail(name: "chicken", cookMethod: "grilled")])
        XCTAssertEqual(model.items[0].origin, .photo)
        XCTAssertEqual(model.items[0].photoConfidence, "high")
        // Straight to the editor, so the person checks it before anything is sent
        XCTAssertEqual(model.path, [.verify])
        XCTAssertFalse(model.completed, "a recognition must never log by itself")
        XCTAssertEqual(model.photoState, .idle)
    }

    @MainActor
    func testTheGuessedCategoryIsAdoptedOnlyWhenNobodyChoseOne() {
        let auto = model()
        auto.apply(read(mealCategory: .dinner))
        XCTAssertEqual(auto.mealType, .dinner)

        let chosen = model()
        chosen.chooseMealType(.breakfast)
        chosen.apply(read(mealCategory: .dinner))
        XCTAssertEqual(chosen.mealType, .breakfast, "a guess must not overwrite a deliberate choice")
    }

    @MainActor
    func testTheDietaryFlagsAreUnionedIntoTheOnesAlreadySet() {
        let model = model()
        model.flags = [.nuts]
        model.apply(read(gluten: true, dairy: true, grains: false))
        XCTAssertEqual(model.flags, [.nuts, .gluten, .dairy])
    }

    @MainActor
    func testAnUnreadablePhotoLeavesTheTypedPathAlone() {
        let model = model()
        model.newFoodName = "half-typed pasta"
        model.apply(read(recognized: false, name: "", ingredients: [], message: "We couldn't read that photo."))

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.newFoodName, "half-typed pasta", "whatever they were typing must survive")
        XCTAssertEqual(model.photoState, .failed("We couldn't read that photo."))
        XCTAssertEqual(model.path, [], "a failure must not navigate anywhere")
    }

    @MainActor
    func testARecognitionWithABlankNameIsTreatedAsAFailure() {
        let model = model()
        model.apply(read(name: "   "))
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNotNil(model.photoError)
    }

    @MainActor
    func testDismissingTheErrorClearsIt() {
        let model = model()
        model.apply(read(recognized: false, name: "", message: "nope"))
        XCTAssertNotNil(model.photoError)
        model.dismissPhotoError()
        XCTAssertNil(model.photoError)
        XCTAssertEqual(model.photoState, .idle)
    }

    @MainActor
    func testAFailedReadSurfacesTheServersOwnWording() async {
        let transport = StubTransport(status: 503, body: #"{"detail":"Photo recognition isn't available right now. Type the meal in instead."}"#)
        let session = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: InMemoryTokenStore(), transport: transport)
        let model = LogMealViewModel(env: AppEnvironment(session: session), date: Date())

        await model.recognize(jpeg: Data([0xFF, 0xD8, 0xFF]), kind: .meal)

        XCTAssertEqual(model.photoError, "Photo recognition isn't available right now. Type the meal in instead.")
        XCTAssertTrue(model.items.isEmpty)
    }
}

final class MealPhotoEncodingTests: XCTestCase {
    func testALargePhotoIsScaledDownToTheLongEdge() {
        let fitted = MealPhotoEncoding.fittedSize(for: CGSize(width: 4032, height: 3024))
        XCTAssertEqual(max(fitted.width, fitted.height), MealPhotoEncoding.maxEdge)
        // Aspect ratio holds, so nothing is squashed
        XCTAssertEqual(fitted.width / fitted.height, 4032.0 / 3024.0, accuracy: 0.01)
    }

    func testATallPhotoIsScaledByItsHeight() {
        let fitted = MealPhotoEncoding.fittedSize(for: CGSize(width: 1000, height: 5000))
        XCTAssertEqual(fitted.height, MealPhotoEncoding.maxEdge)
        XCTAssertEqual(fitted.width, 314, accuracy: 1)
    }

    func testASmallPhotoIsLeftAlone() {
        let size = CGSize(width: 800, height: 600)
        XCTAssertEqual(MealPhotoEncoding.fittedSize(for: size), size, "never enlarge; there is nothing to gain")
        XCTAssertEqual(MealPhotoEncoding.scale(for: size), 1)
    }

    func testAZeroSizeDoesNotDivideByZero() {
        XCTAssertEqual(MealPhotoEncoding.scale(for: .zero), 1)
    }
}

final class SevereSymptomGuidanceTests: XCTestCase {
    func testSevereIntensitiesTriggerTheGuidance() {
        XCTAssertTrue(SevereSymptomGuidance.applies(toIntensities: [4]))
        XCTAssertTrue(SevereSymptomGuidance.applies(toIntensities: [5]))
        // One severe symptom among mild ones still counts
        XCTAssertTrue(SevereSymptomGuidance.applies(toIntensities: [1, 2, 5]))
    }

    func testMilderIntensitiesDoNot() {
        XCTAssertFalse(SevereSymptomGuidance.applies(toIntensities: [1, 2, 3]))
        XCTAssertFalse(SevereSymptomGuidance.applies(toIntensities: []))
    }

    func testTheThresholdAgreesWithTheSeverityScale() {
        // If these drift, the guidance fires at the wrong point and the
        // onboarding disclaimer's promise becomes wrong in one direction.
        XCTAssertEqual(SeverityMapping.severity(forIntensity: SevereSymptomGuidance.threshold), "Severe")
        XCTAssertNotEqual(SeverityMapping.severity(forIntensity: SevereSymptomGuidance.threshold - 1), "Severe")
    }

    func testTheMessageDirectsToMedicalCare() {
        // The disclaimer says users are "directed within the app to seek medical
        // attention"; this is the text that has to honour it.
        XCTAssertTrue(SevereSymptomGuidance.message.contains("doctor"))
        XCTAssertTrue(SevereSymptomGuidance.message.contains("medical attention"))
    }
}

final class OnboardingDisclaimerTests: XCTestCase {
    @MainActor
    private func model(transport: StubTransport) -> OnboardingViewModel {
        let session = AuthSession.make(
            baseURL: URL(string: "https://api.example")!,
            tokenStore: InMemoryTokenStore(),
            transport: transport
        )
        return OnboardingViewModel(env: AppEnvironment(session: session))
    }

    @MainActor
    func testTheDisclaimerStepIsLastAndBlocksUntilAgreed() async {
        let transport = StubTransport(status: 200, body: #"{"version":"2026-10-08","text":"Not a diagnostic tool."}"#)
        let model = model(transport: transport)

        XCTAssertEqual(OnboardingViewModel.Step.allCases.last, .disclaimer)

        model.step = .disclaimer
        XCTAssertFalse(model.canContinue, "nothing loaded yet, so there is nothing to agree to")

        await model.loadDisclaimer()
        XCTAssertEqual(model.disclaimer?.version, "2026-10-08")
        XCTAssertFalse(model.canContinue, "loaded, but not yet agreed")

        model.disclaimerAgreed = true
        XCTAssertTrue(model.canContinue)
    }

    @MainActor
    func testAgreementCannotBeGivenWhenTheTextFailedToLoad() async {
        let transport = StubTransport(status: 503, body: #"{"detail":"nope"}"#)
        let model = model(transport: transport)
        model.step = .disclaimer

        await model.loadDisclaimer()

        XCTAssertTrue(model.disclaimerLoadFailed)
        XCTAssertNil(model.disclaimer)
        // Even if the flag were somehow set, there is no text to agree to.
        model.disclaimerAgreed = true
        XCTAssertFalse(model.canContinue, "no bundled copy on purpose; the step cannot be skipped")
    }
}
