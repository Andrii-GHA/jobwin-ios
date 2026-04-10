import SwiftUI

@main
struct JobWinApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushAppDelegate
    @State private var appEnvironment = AppEnvironment()
    @State private var sessionStore: SessionStore

    init() {
        let environment = AppEnvironment()
        _appEnvironment = State(initialValue: environment)
        _sessionStore = State(initialValue: SessionStore(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(sessionStore: sessionStore)
                .task {
                    await sessionStore.restoreIfPossible()
                }
        }
    }
}
