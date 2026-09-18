import SwiftUI

/// Filled blue call to action.
public struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(TTFont.cardTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.pinnedButton, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// White outlined button.
public struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let emoji: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, emoji: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.emoji = emoji
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let emoji { Text(emoji) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(TTFont.cardTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(TTColor.navy)
            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.pinnedButton, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.pinnedButton, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Round white icon button (back, bell, settings).
public struct IconCircleButton: View {
    let systemImage: String
    let showsDot: Bool
    let action: () -> Void

    public init(systemImage: String, showsDot: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.showsDot = showsDot
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TTColor.primary)
                .frame(width: 44, height: 44)
                .background(TTColor.card, in: Circle())
                .overlay(Circle().stroke(TTColor.cardBorder, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle().fill(TTColor.success).frame(width: 9, height: 9).offset(x: -6, y: 6)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Bar pinned above the tab bar holding the primary action.
public struct PinnedBottomBar<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, TTSpacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(TTColor.background.opacity(0.96))
            .overlay(alignment: .top) { Rectangle().fill(TTColor.cardBorder).frame(height: 1) }
    }
}
