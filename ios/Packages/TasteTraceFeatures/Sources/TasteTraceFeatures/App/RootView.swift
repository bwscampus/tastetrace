import SwiftUI
import TasteTraceCore
import TasteTraceUI

/// Entry point for the app target: decides between auth and the tabs.
public struct RootView: View {
    @State private var env: AppEnvironment
    @State private var router = Router()

    public init(env: AppEnvironment) {
        _env = State(initialValue: env)
    }

    public var body: some View {
        Group {
            switch env.session.state {
            case .unknown:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(TTColor.background)
            case .signedOut:
                AuthView(model: AuthViewModel(session: env.session))
            case .signedIn:
                MainTabView()
            }
        }
        .environment(env)
        .environment(router)
        .tint(TTColor.primary)
        .task {
            await env.session.restore()
            if env.session.user != nil { await env.syncTimezone() }
        }
        .onChange(of: env.session.state) { _, state in
            if case .signedIn = state { Task { await env.syncTimezone() } }
        }
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.todayPath) {
                TodayView(env: env).navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
            .tag(AppTab.today)

            NavigationStack(path: $router.historyPath) {
                HistoryView(env: env).navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.systemImage) }
            .tag(AppTab.history)

            NavigationStack(path: $router.digestPath) {
                PlaceholderScreen(title: "Weekly Health Digest", message: "Trends, symptoms and food suspects arrive in the next milestone.")
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(AppTab.digest.title, systemImage: AppTab.digest.systemImage) }
            .tag(AppTab.digest)

            NavigationStack(path: $router.triggersPath) {
                PlaceholderScreen(title: "Trigger Insights", message: "Symptom-specific confidence tiers arrive in the next milestone.")
            }
            .tabItem { Label(AppTab.triggers.title, systemImage: AppTab.triggers.systemImage) }
            .tag(AppTab.triggers)
        }
        .sheet(item: $router.sheet) { sheet in
            SheetHost(sheet: sheet)
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .coverage(let date):
            CoverageView(date: date)
        case .digest, .suspects, .symptomDigest:
            PlaceholderScreen(title: "Weekly Health Digest", message: "Coming in the digest milestone.")
        }
    }
}

/// Presents the modal flows; real screens replace the placeholders milestone by milestone.
struct SheetHost: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    let sheet: AppSheet

    var body: some View {
        if case .logMeal(let date) = sheet {
            // Owns its own NavigationStack (two steps) and Close button
            LogMealFlow(env: env, date: date)
        } else if case .quickLog(let date) = sheet {
            NavigationStack { QuickLogView(env: env, date: date) }
        } else {
            NavigationStack {
                sheetContent
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { router.sheet = nil } }
                    }
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch sheet {
        case .logMeal:
            EmptyView()
        case .quickLog(let date):
            QuickLogView(env: env, date: date)
        case .profile:
            ProfileStub()
        case .notifications:
            PlaceholderScreen(title: "Notifications", message: "Reminders arrive in a later milestone.")
        case .editMeal(let id):
            EditMealView(mealId: id)
        case .editSymptom(let id):
            EditSymptomView(symptomId: id)
        }
    }
}

/// Minimal profile until the full screen lands: shows the user and signs out.
struct ProfileStub: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router

    var body: some View {
        TTScreen {
            if let user = env.session.user {
                TTCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.shownName).font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
                        Text(user.email).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                }
            }
            SecondaryButton("Sign Out of Account", systemImage: "rectangle.portrait.and.arrow.right") {
                Task { await env.session.signOut(); router.sheet = nil }
            }
        }
        .navigationTitle("User Profile")
    }
}

struct PlaceholderScreen: View {
    let title: String
    let message: String

    var body: some View {
        EmptyStateView(emoji: "🛠️", title: title, message: message)
            .background(TTColor.background)
    }
}
