import SwiftUI
import TasteTraceFeatures

// The app target is a thin shell; every screen lives in Packages/TasteTraceFeatures.
@main
struct TasteTraceApp: App {
    @State private var environment = AppEnvironment.live(baseURL: AppEnvironment.baseURLFromBundle())

    var body: some Scene {
        WindowGroup {
            RootView(env: environment)
        }
    }
}
