import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ActivityStore {
    var snapshot: ActivitySnapshotDTO?
    var isLoading = false
    var errorMessage: String?

    var unreadCount: Int {
        snapshot?.unreadCount ?? 0
    }

    func refresh(using sessionStore: SessionStore, limit: Int = 24) async {
        guard sessionStore.isAuthenticated, let client = sessionStore.makeAPIClient() else {
            snapshot = nil
            errorMessage = nil
            return
        }

        if isLoading { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            snapshot = try await client.get(MobileAPI.activityFeed(limit: limit))
            syncApplicationBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead(using sessionStore: SessionStore) async {
        guard sessionStore.isAuthenticated, let client = sessionStore.makeAPIClient() else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            snapshot = try await client.post(MobileAPI.activityRoot, body: MarkAllActivityReadBody(action: "markAllRead"))
            syncApplicationBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePreferences(using sessionStore: SessionStore, preferences: NotificationPreferencesDTO) async {
        guard sessionStore.isAuthenticated, let client = sessionStore.makeAPIClient() else { return }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            snapshot = try await client.patch(MobileAPI.activityRoot, body: ActivityPreferencesPatchBody(preferences: preferences))
            syncApplicationBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        snapshot = nil
        errorMessage = nil
        isLoading = false
        syncApplicationBadge()
    }

    private func syncApplicationBadge() {
        UIApplication.shared.applicationIconBadgeNumber = unreadCount
    }
}
