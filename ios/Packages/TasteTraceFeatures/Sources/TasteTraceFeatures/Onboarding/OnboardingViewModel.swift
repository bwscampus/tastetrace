import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// How the user wants their journal shared; stored on the profile as the raw value.
enum DataSharingChoice: String, CaseIterable, Identifiable {
    case `private`, practitioner, research

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .private: return "🔒"
        case .practitioner: return "🩺"
        case .research: return "🔬"
        }
    }

    var title: String {
        switch self {
        case .private: return "Keep it private"
        case .practitioner: return "Share with my care team"
        case .research: return "Contribute anonymized data"
        }
    }

    var detail: String {
        switch self {
        case .private: return "Only you see your journal. You can still export it yourself at any time."
        case .practitioner: return "Get practitioner-ready reports to send to your doctor or dietitian."
        case .research: return "Help improve pattern detection with de-identified data. Your name and email are never included."
        }
    }
}

/// The first-run questions shown once after an account is created.
@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case about, purpose, sharing, meals, triggers

        var title: String {
            switch self {
            case .about: return "About you"
            case .purpose: return "What brings you to TasteTrace?"
            case .sharing: return "How should your data be shared?"
            case .meals: return "When do you usually eat?"
            case .triggers: return "How sure before we flag a trigger?"
            }
        }

        var subtitle: String {
            switch self {
            case .about: return "Confirm the name and email on your account."
            case .purpose: return "We'll tailor your digests to what you're after."
            case .sharing: return "You can change this anytime in your profile."
            case .meals: return "We'll nudge you to log each meal shortly after you eat."
            case .triggers: return "The minimum number of flares before a food can be called a trigger."
            }
        }
    }

    static let purposeOptions = [
        "🔍 Find foods that trigger my symptoms",
        "🩺 Manage a diagnosed condition (IBS, celiac, reflux…)",
        "🥗 Run an elimination diet",
        "📋 Keep a log for my doctor or dietitian",
        "💡 Understand my eating habits",
    ]
    static let otherPurpose = "✏️ Something else"

    var step: Step = .about
    var firstName: String
    var lastName: String
    let email: String
    var purpose: String?
    var customPurpose = ""
    var sharing: DataSharingChoice?
    var breakfastTime: Date
    var lunchTime: Date
    var dinnerTime: Date
    var mealRemindersEnabled = true
    var minTriggerCount = UserSettings().minTriggerCount
    var isSaving = false
    var error: String?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
        let user = env.session.user
        firstName = user?.firstName ?? ""
        lastName = user?.lastName ?? ""
        email = user?.email ?? ""
        let defaults = UserSettings()
        breakfastTime = ReminderScheduler.date(fromHHMM: defaults.breakfastTime, math: env.dateMath)
        lunchTime = ReminderScheduler.date(fromHHMM: defaults.lunchTime, math: env.dateMath)
        dinnerTime = ReminderScheduler.date(fromHHMM: defaults.dinnerTime, math: env.dateMath)
    }

    var stepNumber: Int { step.rawValue + 1 }
    var stepCount: Int { Step.allCases.count }
    var isFirstStep: Bool { step == Step.allCases.first }
    var isLastStep: Bool { step == Step.allCases.last }

    /// The purpose saved to the profile: the chosen option without its emoji, or the typed answer.
    var resolvedPurpose: String {
        guard let purpose else { return "" }
        if purpose == Self.otherPurpose { return customPurpose.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(purpose.drop(while: { !$0.isLetter }))
    }

    var canContinue: Bool {
        guard !isSaving else { return false }
        switch step {
        case .about: return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .purpose: return !resolvedPurpose.isEmpty
        case .sharing: return sharing != nil
        case .meals, .triggers: return true
        }
    }

    func back() {
        error = nil
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func next() async {
        guard canContinue else { return }
        error = nil
        if let following = Step(rawValue: step.rawValue + 1) {
            step = following
        } else {
            await finish()
        }
    }

    /// Saves the answers, schedules the meal reminders and marks onboarding done.
    func finish() async {
        isSaving = true
        defer { isSaving = false }
        let math = env.dateMath
        do {
            let settings = try await env.run {
                try await env.api.updateSettings(SettingsPatch(
                    minTriggerCount: minTriggerCount,
                    mealCheckInsEnabled: mealRemindersEnabled,
                    breakfastTime: ReminderScheduler.hhmm(from: breakfastTime, math: math),
                    lunchTime: ReminderScheduler.hhmm(from: lunchTime, math: math),
                    dinnerTime: ReminderScheduler.hhmm(from: dinnerTime, math: math)
                ))
            }
            // Asks for notification permission when reminders are on
            await env.reminders.sync(settings: settings, math: math)
            _ = try await env.run {
                try await env.api.updateProfile(ProfilePatch(
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces),
                    discoveryPurpose: resolvedPurpose,
                    dataSharing: sharing?.rawValue,
                    onboardingCompleted: true
                ))
            }
            // Swaps the root view over to the tabs
            await env.session.refreshUser()
            if env.session.user?.needsOnboarding == true {
                error = "Your answers were saved, but the TasteTrace server didn't confirm onboarding is done. It may need updating. Please try again shortly."
            }
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async { await env.session.signOut() }
}
