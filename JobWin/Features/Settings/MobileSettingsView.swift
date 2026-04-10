import SwiftUI
import UIKit
import UserNotifications

@Observable
final class MobileSettingsModel {
    private let client: APIClient

    var isLoading = false
    var errorMessage: String?
    var bootstrap: MobileBootstrapDTO?
    var isRefreshingPush = false
    var isUpdatingPreferences = false

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            bootstrap = try await client.get(MobileAPI.bootstrap)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshPush(using sessionStore: SessionStore) async {
        if isRefreshingPush { return }
        isRefreshingPush = true

        defer {
            isRefreshingPush = false
        }

        let pushService = sessionStore.environment.pushService
        await pushService.configure(using: sessionStore)
        await pushService.reloadAuthorizationStatus()
        await pushService.syncRegistrationIfPossible(using: sessionStore)
        await load()
    }

    func updatePreferences(using sessionStore: SessionStore, preferences: NotificationPreferencesDTO) async {
        if isUpdatingPreferences { return }
        isUpdatingPreferences = true

        defer {
            isUpdatingPreferences = false
        }

        await sessionStore.environment.activityStore.updatePreferences(using: sessionStore, preferences: preferences)
        if let activityError = sessionStore.environment.activityStore.errorMessage {
            errorMessage = activityError
        }
    }
}

struct MobileSettingsView: View {
    let sessionStore: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var model: MobileSettingsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model: model)
                } else {
                    LoadingStateView(title: "Preparing settings...")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await sessionStore.environment.pushService.reloadAuthorizationStatus()
                            await model?.load()
                        }
                    }
                    .disabled(model?.isLoading == true)
                }
            }
            .task {
                guard let client = sessionStore.makeAPIClient() else { return }
                if model == nil {
                    model = MobileSettingsModel(client: client)
                }

                await sessionStore.environment.pushService.reloadAuthorizationStatus()
                await sessionStore.environment.activityStore.refresh(using: sessionStore, limit: 24)
                await model?.load()
            }
        }
    }

    @ViewBuilder
    private func content(model: MobileSettingsModel) -> some View {
        if model.isLoading, model.bootstrap == nil {
            LoadingStateView(title: "Loading settings...")
        } else if let errorMessage = model.errorMessage, model.bootstrap == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
            let pushService = sessionStore.environment.pushService

            Form {
                Section("Account") {
                    DetailLine(
                        title: sessionStore.identity?.email ?? "Signed-in user",
                        subtitle: JobWinFormatting.bulletJoin(
                            sessionStore.identity?.mobileRole.map(JobWinFormatting.displayStatus),
                            sessionStore.identity?.workspaceId
                        )
                    )
                }

                if let bootstrap = model.bootstrap {
                    Section("Workspace") {
                        DetailLine(
                            title: bootstrap.workspace.businessName ?? bootstrap.workspace.name ?? "JobWin workspace",
                            subtitle: bootstrap.workspace.id
                        )

                        DetailLine(
                            title: bootstrap.aiPhone.active ? "AI phone active" : "AI phone inactive",
                            subtitle: bootstrap.aiPhone.phoneNumber ?? "No AI number assigned"
                        )
                    }
                }

                Section("Push diagnostics") {
                    DetailLine(
                        title: "Authorization",
                        subtitle: pushAuthorizationLabel(pushService.authorizationStatus)
                    )
                    DetailLine(
                        title: "Device ID",
                        subtitle: pushService.deviceId
                    )
                    DetailLine(
                        title: "Device token",
                        subtitle: pushService.deviceToken == nil ? "Not received yet" : "Received"
                    )
                    DetailLine(
                        title: "Registered token",
                        subtitle: pushService.latestRegisteredTokenId ?? "Not registered"
                    )

                    if let latestErrorMessage = pushService.latestErrorMessage {
                        Text(latestErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let preferences = sessionStore.environment.activityStore.snapshot?.preferences {
                    Section("Notification preferences") {
                        Toggle("Orders", isOn: binding(for: \.orders, from: preferences))
                        Toggle("Clients", isOn: binding(for: \.clients, from: preferences))
                        Toggle("Bookings", isOn: binding(for: \.bookings, from: preferences))
                        Toggle("Payments", isOn: binding(for: \.payments, from: preferences))
                        Toggle("AI calls", isOn: binding(for: \.aiCalls, from: preferences))
                        Toggle("Estimates", isOn: binding(for: \.estimates, from: preferences))
                        Toggle("System", isOn: binding(for: \.system, from: preferences))
                        Toggle("Popup alerts", isOn: binding(for: \.popupAlerts, from: preferences))
                    }
                    .disabled(model.isUpdatingPreferences || sessionStore.environment.activityStore.isLoading)
                }

                Section("Actions") {
                    Button(model.isRefreshingPush ? "Refreshing..." : "Enable / refresh notifications") {
                        Task {
                            await model.refreshPush(using: sessionStore)
                        }
                    }
                    .disabled(model.isRefreshingPush || !sessionStore.isAuthenticated)

                    if pushService.authorizationStatus == .denied {
                        Button("Open iPhone Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }

                    Button("Sign out", role: .destructive) {
                        sessionStore.signOut()
                        dismiss()
                    }
                }
            }
        }
    }

    private func pushAuthorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    private func binding(
        for keyPath: WritableKeyPath<NotificationPreferencesDTO, Bool>,
        from preferences: NotificationPreferencesDTO
    ) -> Binding<Bool> {
        Binding(
            get: {
                sessionStore.environment.activityStore.snapshot?.preferences[keyPath: keyPath] ?? preferences[keyPath: keyPath]
            },
            set: { newValue in
                var next = sessionStore.environment.activityStore.snapshot?.preferences ?? preferences
                next[keyPath: keyPath] = newValue
                Task {
                    await model?.updatePreferences(using: sessionStore, preferences: next)
                }
            }
        )
    }
}
