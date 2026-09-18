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
