import SwiftUI

/// White card with the thin blue-grey border used everywhere in the mockups.
public struct TTCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = TTSpacing.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
    }
}

/// Navy-to-blue gradient card for hero stats.
public struct HeroGradientCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TTSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TTGradient.hero, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
            .foregroundStyle(.white)
    }
}

/// Uppercase tracked label above a section.
public struct SectionLabel: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(TTFont.sectionLabel)
            .tracking(1.2)
            .foregroundStyle(TTColor.textSecondary)
    }
}
