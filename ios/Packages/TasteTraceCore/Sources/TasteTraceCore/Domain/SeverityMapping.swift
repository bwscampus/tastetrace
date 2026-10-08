import Foundation

/// Mirrors app/shared/severity.ts.
public enum SeverityMapping {
    public static func severity(forIntensity intensity: Int) -> String {
        switch intensity {
        case ...2: return "Mild"
        case 3: return "Moderate"
        default: return "Severe"
        }
    }

    public static func intensity(forSeverity severity: String) -> Int {
        switch severity {
        case "Mild": return 2
        case "Severe": return 4
        default: return 3
        }
    }

    /// Discomfort on the digest's 10-point scale.
    public static func discomfortScore(intensity: Int) -> Double { Double(intensity) * 2 }
}

/// What the app says when someone logs a severe symptom.
///
/// The medical disclaimer shown at onboarding states that users with severe or
/// worsening symptoms "are directed within the app to seek medical attention
/// rather than rely on the app's pattern-tracking features". This is that
/// direction. If it is removed, the disclaimer becomes untrue.
public enum SevereSymptomGuidance {
    /// Intensity at or above this reads as Severe; keep in step with `severityName`.
    public static let threshold = 4

    public static let message = """
        That's a severe symptom. Please contact a doctor or seek medical attention rather than \
        waiting to see what TasteTrace finds. Pattern tracking looks backwards over weeks; it is \
        not a judgement about what you need right now.
        """

    /// True when any of the intensities just logged was severe.
    public static func applies(toIntensities intensities: some Sequence<Int>) -> Bool {
        intensities.contains { $0 >= threshold }
    }
}
