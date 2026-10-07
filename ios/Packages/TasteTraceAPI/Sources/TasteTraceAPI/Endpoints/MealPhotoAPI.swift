import Foundation

/// Which of the two things the photo shows. A label is transcribed; a plate is
/// identified.
public enum MealPhotoKind: String, Codable, Sendable {
    case meal
    case label
}

/// `POST /api/ai/meal-photo`
///
/// Deliberately the same fields `MealCreate` accepts, so a recognition can be
/// posted straight back as a meal with no mapping in between. `ingredients` and
/// `mealCategory` are the existing types, not new ones.
///
/// Every server-side failure arrives here as `recognized == false` with a
/// `message` to show, rather than as an error — the screen must always have
/// something to say, and typing the meal in is never blocked.
public struct MealPhotoRecognition: Codable, Equatable, Sendable {
    public let recognized: Bool
    public let name: String
    public let ingredients: [IngredientDetail]
    public let mealCategory: MealType?
    public let containsGluten: Bool
    public let containsDairy: Bool
    public let containsGrains: Bool
    public let containsSugar: Bool
    public let containsNuts: Bool
    /// high | medium | low. Drives how loudly the editor asks for a check.
    public let confidence: String
    public let kind: String
    public let model: String?
    public let message: String?

    public init(
        recognized: Bool,
        name: String = "",
        ingredients: [IngredientDetail] = [],
        mealCategory: MealType? = nil,
        containsGluten: Bool = false,
        containsDairy: Bool = false,
        containsGrains: Bool = false,
        containsSugar: Bool = false,
        containsNuts: Bool = false,
        confidence: String = "low",
        kind: String = "meal",
        model: String? = nil,
        message: String? = nil
    ) {
        self.recognized = recognized
        self.name = name
        self.ingredients = ingredients
        self.mealCategory = mealCategory
        self.containsGluten = containsGluten
        self.containsDairy = containsDairy
        self.containsGrains = containsGrains
        self.containsSugar = containsSugar
        self.containsNuts = containsNuts
        self.confidence = confidence
        self.kind = kind
        self.model = model
        self.message = message
    }

    /// The dietary flags as the set the log flow carries them in.
    public var flagNames: [String] {
        var names: [String] = []
        if containsGluten { names.append("gluten") }
        if containsDairy { names.append("dairy") }
        if containsGrains { names.append("grains") }
        if containsSugar { names.append("sugar") }
        if containsNuts { names.append("nuts") }
        return names
    }
}

public extension APIClient {
    /// Ask the server what a photo shows. `jpeg` must already be downscaled and
    /// JPEG-encoded: the API rejects HEIC, which is what the camera produces by
    /// default, and a full-resolution photo costs roughly twice the tokens for
    /// no better reading.
    func recognizeMealPhoto(
        jpeg: Data,
        kind: MealPhotoKind = .meal,
        mealType: MealType? = nil,
        hint: String? = nil
    ) async throws -> MealPhotoRecognition {
        struct Body: Encodable {
            let imageBase64: String
            let kind: String
            let mealType: String?
            let hint: String?
        }
        let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await request(
            .post,
            "/api/ai/meal-photo",
            body: Body(
                imageBase64: jpeg.base64EncodedString(),
                kind: kind.rawValue,
                mealType: mealType?.rawValue,
                hint: (trimmed?.isEmpty == false) ? trimmed : nil
            )
        )
    }
}
