import SwiftUI

/// Circular progress ring with a label in the middle (coverage 2/3).
public struct RingProgress<Label: View>: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color
    let label: Label

    public init(progress: Double, lineWidth: CGFloat = 8, color: Color = TTColor.primary, @ViewBuilder label: () -> Label) {
        self.progress = min(max(progress, 0), 1)
        self.lineWidth = lineWidth
        self.color = color
        self.label = label()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(TTColor.dot.opacity(0.6), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            label
        }
    }
}

/// Emoji inside a tinted circle (timeline and entry cards).
public struct EmojiCircle: View {
    let emoji: String
    let size: CGFloat
    let tint: Color

    public init(_ emoji: String, size: CGFloat = 44, tint: Color = TTColor.infoTint) {
        self.emoji = emoji
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .overlay(Circle().stroke(TTColor.cardBorder, lineWidth: 1))
    }
}

/// Dot under a day in the week strip.
public enum DayDot {
    case none, meal, ok, symptom, today

    public var color: Color {
        switch self {
        case .none: return .clear
        case .meal: return TTColor.primary
        case .ok: return TTColor.success
        case .symptom: return TTColor.warning
        case .today: return TTColor.primary
        }
    }
}

/// Soft tinted banner with an emoji/icon and text (tips, info).
public struct InfoBanner: View {
    let emoji: String
    let title: String?
    let message: String
    let tone: BadgeTone

    public init(emoji: String, title: String? = nil, message: String, tone: BadgeTone = .info) {
        self.emoji = emoji
        self.title = title
        self.message = message
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy) }
                Text(message).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TTSpacing.card)
        .background(tone.background, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
    }
}

/// Dashed outline placeholder (pending slot, save suggestion).
public struct DashedPlaceholderCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(TTSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TTColor.infoTint.opacity(0.6), in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.primary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }
}

/// Dark rounded toast at the bottom of Today.
public struct ToastView: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(TTFont.bodySemibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(TTColor.toast, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
    }
}

/// Full-screen friendly empty state.
public struct EmptyStateView: View {
    let emoji: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(emoji: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.emoji = emoji
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.system(size: 56))
            Text(title).font(TTFont.screenTitle).foregroundStyle(TTColor.navy).multilineTextAlignment(.center)
            Text(message).font(TTFont.body).foregroundStyle(TTColor.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TTFont.bodySemibold)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .foregroundStyle(TTColor.primary)
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile).stroke(TTColor.primary, lineWidth: 1.5))
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
