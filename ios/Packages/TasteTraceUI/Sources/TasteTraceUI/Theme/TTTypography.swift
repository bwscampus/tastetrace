import SwiftUI

public enum TTFont {
    public static let heroNumber = Font.system(size: 40, weight: .bold, design: .rounded)
    public static let screenTitle = Font.system(size: 24, weight: .bold)
    public static let cardTitle = Font.system(size: 18, weight: .semibold)
    public static let body = Font.system(size: 16)
    public static let bodySemibold = Font.system(size: 16, weight: .semibold)
    public static let caption = Font.system(size: 13)
    public static let captionSemibold = Font.system(size: 13, weight: .semibold)
    public static let sectionLabel = Font.system(size: 13, weight: .semibold)
}

public enum TTRadius {
    public static let card: CGFloat = 20
    public static let tile: CGFloat = 16
    public static let button: CGFloat = 16
    public static let pinnedButton: CGFloat = 20
    public static let chip: CGFloat = 999
}

public enum TTSpacing {
    public static let screen: CGFloat = 16
    public static let card: CGFloat = 16
    public static let stack: CGFloat = 12
    public static let tight: CGFloat = 8
}

public enum TTGradient {
    public static let hero = LinearGradient(colors: [TTColor.heroTop, TTColor.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
}
