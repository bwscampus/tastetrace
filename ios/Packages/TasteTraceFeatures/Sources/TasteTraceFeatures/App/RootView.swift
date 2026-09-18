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
            if env.session.user != nil { await env.syncTimezone(); await env.syncPreferences() }
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
                DigestView(env: env)
                    .navigationDestination(for: Route.self) { destination(for: $0) }
            }
            .tabItem { Label(AppTab.digest.title, systemImage: AppTab.digest.systemImage) }
            .tag(AppTab.digest)

            NavigationStack(path: $router.triggersPath) {
                TriggerInsightsView(env: env)
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
        case .digest(let weekStart):
            DigestView(env: env, weekStart: weekStart)
        case .suspects(let weekStart):
            DigestView(env: env, weekStart: weekStart, segment: .suspects)
        case .symptomDigest(let weekStart):
            DigestView(env: env, weekStart: weekStart, segment: .symptoms)
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
            ProfileView(env: env)
        case .notifications:
            NotificationsView()
        case .editMeal(let id):
            EditMealView(mealId: id)
        case .editSymptom(let id):
            EditSymptomView(symptomId: id)
        case .export(let kind, let weekStart):
            ExportView(env: env, kind: kind.flatMap(ReportKind.init(rawValue:)), weekStart: weekStart)
        }
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
