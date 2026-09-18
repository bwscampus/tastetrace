import SwiftUI

public enum BadgeTone {
    case neutral, info, success, warning, danger, primary

    public var foreground: Color {
        switch self {
        case .neutral: return TTColor.textSecondary
        case .info: return TTColor.primary
        case .success: return TTColor.success
        case .warning: return TTColor.warning
        case .danger: return TTColor.danger
        case .primary: return .white
        }
    }

    public var background: Color {
        switch self {
        case .neutral: return TTColor.neutralTint
        case .info: return TTColor.infoTint
        case .success: return TTColor.successTint
        case .warning: return TTColor.warningTint
        case .danger: return TTColor.dangerTint
        case .primary: return TTColor.primary
        }
    }
}

/// Small rounded status label ("Logged", "Suspicious Trigger", "5-Day Streak").
public struct StatusBadge: View {
    let text: String
    let tone: BadgeTone
    let uppercased: Bool

    public init(_ text: String, tone: BadgeTone = .neutral, uppercased: Bool = false) {
        self.text = text
        self.tone = tone
        self.uppercased = uppercased
    }

    public var body: some View {
        Text(uppercased ? text.uppercased() : text)
            .font(TTFont.captionSemibold)
            .tracking(uppercased ? 0.8 : 0)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: Capsule())
    }
}

/// Selectable pill used for filters (symptom chips, day chips).
public struct TTChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    public init(_ text: String, selected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(TTFont.bodySemibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? .white : TTColor.navy)
                .background(selected ? TTColor.primary : TTColor.card, in: Capsule())
                .overlay(Capsule().stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Pill-shaped segmented control (Trends / Symptoms / Suspects).
public struct TTSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    public init(options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    Text(label(option))
                        .font(TTFont.bodySemibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selection == option ? TTColor.primary : TTColor.textSecondary)
                        .background(selection == option ? TTColor.card : .clear, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(TTColor.neutralTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
    }
}
