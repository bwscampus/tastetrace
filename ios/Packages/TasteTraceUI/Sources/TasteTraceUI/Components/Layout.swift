import SwiftUI

/// Standard screen scaffold: tinted background, scrolling content with the
/// screen gutter, optional pinned bottom bar.
public struct TTScreen<Content: View, Bottom: View>: View {
    let content: Content
    let bottom: Bottom

    public init(@ViewBuilder content: () -> Content, @ViewBuilder bottom: () -> Bottom) {
        self.content = content()
        self.bottom = bottom()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.stack) { content }
                .padding(.horizontal, TTSpacing.screen)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(TTColor.background)
        .safeAreaInset(edge: .bottom) { bottom }
    }
}

public extension TTScreen where Bottom == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, bottom: { EmptyView() })
    }
}

/// Title + subtitle pair used in navigation headers.
public struct ScreenHeading: View {
    let title: String
    let subtitle: String?
    let subtitleUppercased: Bool

    public init(_ title: String, subtitle: String? = nil, subtitleUppercased: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleUppercased = subtitleUppercased
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(title).font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
            if let subtitle {
                Text(subtitleUppercased ? subtitle.uppercased() : subtitle)
                    .font(subtitleUppercased ? TTFont.captionSemibold : TTFont.body)
                    .tracking(subtitleUppercased ? 1 : 0)
                    .foregroundStyle(subtitleUppercased ? TTColor.primary : TTColor.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// Inline error line under a form or list.
public struct ErrorText: View {
    let message: String?
    public init(_ message: String?) { self.message = message }
    public var body: some View {
        if let message {
            Text(message).font(TTFont.caption).foregroundStyle(TTColor.danger)
        }
    }
}
