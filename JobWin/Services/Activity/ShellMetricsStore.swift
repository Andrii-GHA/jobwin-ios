import Foundation
import Observation

@MainActor
@Observable
final class ShellMetricsStore {
    var todayOrdersCount = 0
    var unreadInboxCount = 0
    var followUpCount = 0
    var urgentTasksCount = 0
    var isLoading = false

    func refresh(using sessionStore: SessionStore) async {
        guard sessionStore.isAuthenticated, let client = sessionStore.makeAPIClient() else {
            clear()
            return
        }

        await refresh(using: client)
    }

    func refresh(using client: APIClient) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let payload: HomeOperationsDTO = try await client.get(MobileAPI.home)
            replace(with: payload)
        } catch {}
    }

    func replace(with payload: HomeOperationsDTO?) {
        todayOrdersCount = payload?.todayOrders.count ?? 0
        unreadInboxCount = payload?.unreadInboxCount ?? 0
        followUpCount = payload?.followUpQueue.count ?? 0
        urgentTasksCount = payload?.urgentTasks.count ?? 0
    }

    func clear() {
        todayOrdersCount = 0
        unreadInboxCount = 0
        followUpCount = 0
        urgentTasksCount = 0
        isLoading = false
    }
}
