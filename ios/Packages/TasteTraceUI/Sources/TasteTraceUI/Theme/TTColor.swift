import SwiftUI

/// Colors sampled from the mockups.
public enum TTColor {
    public static let background = Color(hex: 0xF3F6FC)
    public static let card = Color.white
    public static let cardBorder = Color(hex: 0xDCE5F5)
    public static let primary = Color(hex: 0x2563EB)
    public static let primaryDark = Color(hex: 0x1E4FC4)
    public static let navy = Color(hex: 0x1B2559)
    public static let textSecondary = Color(hex: 0x5B6B8C)
    public static let heroTop = Color(hex: 0x1E2A4A)
    public static let heroBottom = Color(hex: 0x2B63D9)
    public static let toast = Color(hex: 0x22304F)
    public static let success = Color(hex: 0x16A34A)
    public static let successTint = Color(hex: 0xE8F8EF)
    public static let warning = Color(hex: 0xF59E0B)
    public static let warningTint = Color(hex: 0xFFF6E5)
    public static let warningBorder = Color(hex: 0xF8C98A)
    public static let danger = Color(hex: 0xDC2626)
    public static let dangerTint = Color(hex: 0xFEE9E9)
    public static let infoTint = Color(hex: 0xE8F0FE)
    public static let neutralTint = Color(hex: 0xEEF2F9)
    public static let dot = Color(hex: 0xC7D2E5)
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
