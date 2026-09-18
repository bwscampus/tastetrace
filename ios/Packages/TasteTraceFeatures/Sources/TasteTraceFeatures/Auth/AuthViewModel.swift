import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

@Observable
@MainActor
final class AuthViewModel {
    enum Mode: String, CaseIterable { case signIn = "Sign In", signUp = "Sign Up" }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var isBusy = false
    var error: String?

    private let session: AuthSession

    init(session: AuthSession) {
        self.session = session
    }

    var canSubmit: Bool {
        let emailOk = email.contains("@") && email.contains(".")
        let passwordOk = password.count >= 6
        let namesOk = mode == .signIn || (!firstName.trimmingCharacters(in: .whitespaces).isEmpty)
        return emailOk && passwordOk && namesOk && !isBusy
    }

    func submit() async {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            switch mode {
            case .signIn:
                try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            case .signUp:
                try await session.register(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                           firstName: firstName.trimmingCharacters(in: .whitespaces),
                                           lastName: lastName.trimmingCharacters(in: .whitespaces))
            }
        } catch APIError.unauthorized {
            error = "Incorrect email or password."
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
