import SwiftUI
import TasteTraceUI

struct AuthView: View {
    @State private var model: AuthViewModel

    init(model: AuthViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TTScreen {
            VStack(spacing: 6) {
                Text("🍽️").font(.system(size: 48))
                Text("TasteTrace").font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
                Text("Connect what you eat to how you feel.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            TTSegmentedControl(options: AuthViewModel.Mode.allCases, selection: $model.mode) { $0.rawValue }

            TTCard {
                VStack(alignment: .leading, spacing: 14) {
                    if model.mode == .signUp {
                        HStack(spacing: 10) {
                            LabeledField("First name", text: $model.firstName)
                            LabeledField("Last name", text: $model.lastName)
                        }
                    }
                    LabeledField("Email", text: $model.email, keyboard: .emailAddress)
                    LabeledField("Password", text: $model.password, secure: true)
                    ErrorText(model.error)
                    PrimaryButton(model.mode == .signIn ? "Sign In" : "Create Account", isLoading: model.isBusy) {
                        Task { await model.submit() }
                    }
                    .opacity(model.canSubmit ? 1 : 0.5)
                    .disabled(!model.canSubmit)
                }
            }

            Text("Passwords need at least 6 characters.")
                .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Caption above a bordered text field.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var keyboard: KeyboardKind = .default

    enum KeyboardKind { case `default`, emailAddress, numberPad }

    init(_ label: String, text: Binding<String>, secure: Bool = false, keyboard: KeyboardKind = .default) {
        self.label = label
        self._text = text
        self.secure = secure
        self.keyboard = keyboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(TTFont.captionSemibold).tracking(0.8).foregroundStyle(TTColor.textSecondary)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .applyKeyboard(keyboard)
                }
            }
            .font(TTFont.body)
            .padding(12)
            .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
        }
    }
}

private extension View {
    @ViewBuilder
    func applyKeyboard(_ kind: LabeledField.KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .default: self
        case .emailAddress: self.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .numberPad: self.keyboardType(.numberPad)
        }
        #else
        self
        #endif
    }
}
