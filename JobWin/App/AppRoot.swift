import SwiftUI

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase

    let sessionStore: SessionStore

    @State private var router = AppRouter()

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                authenticatedShell
            } else {
                AuthView(sessionStore: sessionStore)
            }
        }
        .background(JobWinPalette.canvas.ignoresSafeArea())
        .sheet(item: Binding(
            get: { router.presentedWebDestination },
            set: { router.presentedWebDestination = $0 }
        )) { destination in
            if let url = URL(string: "\(sessionStore.apiBaseURL)\(destination.path)") {
                SafariSheetView(url: url)
            }
        }
        .onOpenURL { url in
            router.handle(
                url: url,
                fullAccess: sessionStore.identity?.fullAccess == true,
                isAuthenticated: sessionStore.isAuthenticated
            )
        }
        .task(id: sessionStore.isAuthenticated) {
            let pushService = sessionStore.environment.pushService
            let locationService = sessionStore.environment.locationService
            if sessionStore.isAuthenticated {
                await pushService.configure(using: sessionStore)
                locationService.configure(using: sessionStore)
                locationService.handleScenePhase(scenePhase)
                await refreshOperatorShell()
            } else {
                sessionStore.environment.shellMetricsStore.clear()
                sessionStore.environment.activityStore.clear()
                sessionStore.environment.pushService.clearSessionState()
                locationService.clearSession()
            }
        }
        .task(id: sessionStore.environment.pushService.deviceToken) {
            guard sessionStore.isAuthenticated else { return }
            await sessionStore.environment.pushService.syncRegistrationIfPossible(using: sessionStore)
        }
        .onChange(of: sessionStore.environment.pushService.pendingRoute) { _, pendingRoute in
            guard let pendingRoute else { return }
            router.open(
                route: pendingRoute,
                fullAccess: sessionStore.identity?.fullAccess == true,
                isAuthenticated: sessionStore.isAuthenticated
            )
            sessionStore.environment.pushService.clearPendingRoute()
            Task { await refreshOperatorShell() }
        }
        .onChange(of: sessionStore.environment.pushService.foregroundRefreshToken) { _, _ in
            guard sessionStore.isAuthenticated else { return }
            Task { await refreshOperatorShell() }
        }
        .onChange(of: scenePhase) { _, phase in
            sessionStore.environment.locationService.handleScenePhase(phase)

            guard phase == .active, sessionStore.isAuthenticated else { return }
            Task { await refreshOperatorShell() }
        }
        .onChange(of: sessionStore.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                router.resetForSignOut()
                return
            }

            router.consumePendingRouteIfPossible(
                fullAccess: sessionStore.identity?.fullAccess == true,
                isAuthenticated: isAuthenticated
            )
        }
    }

    private func refreshOperatorShell() async {
        await sessionStore.environment.pushService.syncRegistrationIfPossible(using: sessionStore)
        await sessionStore.environment.shellMetricsStore.refresh(using: sessionStore)
        await sessionStore.environment.activityStore.refresh(using: sessionStore, limit: 24)
    }

    private var authenticatedShell: some View {
        @Bindable var router = router
        let fullAccess = sessionStore.identity?.fullAccess == true

        return TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                HomeView(sessionStore: sessionStore)
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .tasks:
                            TasksView(sessionStore: sessionStore)
                        case let .task(taskId):
                            TaskDetailView(sessionStore: sessionStore, taskId: taskId)
                        }
                    }
            }
            .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
            .badge(tabBadge(sessionStore.environment.shellMetricsStore.urgentTasksCount))
            .tag(AppTab.home)

            NavigationStack {
                CalendarView(sessionStore: sessionStore)
            }
            .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage) }
            .tag(AppTab.calendar)

            NavigationStack(path: $router.ordersPath) {
                OrdersView(sessionStore: sessionStore)
                    .navigationDestination(for: OrdersRoute.self) { route in
                        switch route {
                        case let .detail(orderId):
                            OrderDetailView(sessionStore: sessionStore, orderId: orderId)
                        }
                    }
            }
            .tabItem { Label(AppTab.orders.title, systemImage: AppTab.orders.systemImage) }
            .badge(tabBadge(sessionStore.environment.shellMetricsStore.todayOrdersCount))
            .tag(AppTab.orders)

            if fullAccess {
                NavigationStack(path: $router.inboxPath) {
                    InboxView(sessionStore: sessionStore)
                        .navigationDestination(for: InboxRoute.self) { route in
                            switch route {
                            case let .detail(threadId):
                                InboxThreadDetailView(sessionStore: sessionStore, threadId: threadId)
                            }
                        }
                }
                .tabItem { Label(AppTab.inbox.title, systemImage: AppTab.inbox.systemImage) }
                .badge(tabBadge(sessionStore.environment.shellMetricsStore.unreadInboxCount))
                .tag(AppTab.inbox)

                NavigationStack(path: $router.clientsPath) {
                    ClientsView(sessionStore: sessionStore)
                        .navigationDestination(for: ClientsRoute.self) { route in
                            switch route {
                            case let .detail(clientId):
                                ClientDetailView(sessionStore: sessionStore, clientId: clientId)
                            }
                        }
                }
                .tabItem { Label(AppTab.clients.title, systemImage: AppTab.clients.systemImage) }
                .badge(tabBadge(sessionStore.environment.shellMetricsStore.followUpCount))
                .tag(AppTab.clients)
            }
        }
        .tint(JobWinPalette.primary)
        .onChange(of: fullAccess) { _, newValue in
            if !newValue && (router.selectedTab == .inbox || router.selectedTab == .clients) {
                router.resetForSignOut()
            }
        }
    }

    private func tabBadge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
