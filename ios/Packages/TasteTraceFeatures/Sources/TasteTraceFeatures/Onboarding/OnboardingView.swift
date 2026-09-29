import SwiftUI
import TasteTraceUI

/// First-run questions, one step per screen, shown until they are answered.
struct OnboardingView: View {
    @State private var model: OnboardingViewModel

    init(model: OnboardingViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STEP \(model.stepNumber) OF \(model.stepCount)")
                        .font(TTFont.captionSemibold).tracking(1).foregroundStyle(TTColor.primary)
                    Spacer()
                    if model.isFirstStep {
                        Button("Sign out") { Task { await model.signOut() } }
                            .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                }
                ProgressView(value: Double(model.stepNumber), total: Double(model.stepCount)).tint(TTColor.primary)
                Text(model.step.title).font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
                Text(model.step.subtitle).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            .padding(.top, 16)

            switch model.step {
            case .about: aboutStep
            case .purpose: purposeStep
            case .sharing: sharingStep
            case .meals: mealsStep
            case .triggers: triggersStep
            }

            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                HStack(spacing: 10) {
                    if !model.isFirstStep {
                        SecondaryButton("Back") { model.back() }
                            .frame(maxWidth: 120)
                    }
                    PrimaryButton(model.isLastStep ? "Finish" : "Continue", isLoading: model.isSaving) {
                        Task { await model.next() }
                    }
                    .opacity(model.canContinue ? 1 : 0.5)
                    .disabled(!model.canContinue)
                }
            }
        }
        .animation(.default, value: model.step)
    }

    private var aboutStep: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    LabeledField("First name", text: $model.firstName)
                    LabeledField("Last name", text: $model.lastName)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("EMAIL").font(TTFont.captionSemibold).tracking(0.8).foregroundStyle(TTColor.textSecondary)
                    Text(model.email).font(TTFont.body).foregroundStyle(TTColor.navy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(TTColor.neutralTint, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                }
            }
        }
    }

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(OnboardingViewModel.purposeOptions + [OnboardingViewModel.otherPurpose], id: \.self) { option in
                OptionRow(title: option, selected: model.purpose == option) { model.purpose = option }
            }
            if model.purpose == OnboardingViewModel.otherPurpose {
                LabeledField("Tell us in a few words", text: $model.customPurpose)
            }
        }
    }

    private var sharingStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DataSharingChoice.allCases) { choice in
                OptionRow(title: "\(choice.emoji) \(choice.title)", detail: choice.detail, selected: model.sharing == choice) {
                    model.sharing = choice
                }
            }
        }
    }

    private var mealsStep: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 14) {
                DatePicker("🌅 Breakfast", selection: $model.breakfastTime, displayedComponents: .hourAndMinute)
                DatePicker("🥪 Lunch", selection: $model.lunchTime, displayedComponents: .hourAndMinute)
                DatePicker("🍝 Dinner", selection: $model.dinnerTime, displayedComponents: .hourAndMinute)
                Divider()
                Toggle("Remind me to log each meal", isOn: $model.mealRemindersEnabled)
                    .font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                Text("Reminders arrive \(ReminderScheduler.checkInDelayMinutes) minutes after each meal time. iOS will ask to allow notifications when you finish.")
                    .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
            }
            .font(TTFont.bodySemibold)
            .foregroundStyle(TTColor.navy)
        }
    }

    private var triggersStep: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: $model.minTriggerCount, in: 1...20) {
                    HStack {
                        Text("Minimum trigger count").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                        Spacer()
                        Text("\(model.minTriggerCount)×").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                    }
                }
                Text("A food needs at least this many flares after eating it before TasteTrace flags it. Lower finds patterns sooner; higher means fewer false alarms. 2 is a good start, and you can change it later under Tracking Rules.")
                    .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
            }
        }
    }
}

/// A tappable answer card with a radio indicator.
private struct OptionRow: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? TTColor.primary : TTColor.cardBorder)
                    .font(.system(size: 20))
            }
            .padding(14)
            .background(selected ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous)
                .stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
