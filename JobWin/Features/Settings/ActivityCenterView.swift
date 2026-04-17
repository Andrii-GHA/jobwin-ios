import SwiftUI

struct ActivityCenterView: View {
    let sessionStore: SessionStore

    @Environment(\.dismiss) private var dismiss

    private var store: ActivityStore {
        sessionStore.environment.activityStore
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading, store.snapshot == nil {
                    LoadingStateView(title: "Loading activity...")
                } else if let errorMessage = store.errorMessage, store.snapshot == nil {
                    ErrorStateView(message: errorMessage) {
                        Task { await store.refresh(using: sessionStore, limit: 40) }
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await store.refresh(using: sessionStore, limit: 40) }
                    }
                    .disabled(store.isLoading)
                }
            }
            .task {
                if store.snapshot == nil {
                    await store.refresh(using: sessionStore, limit: 40)
                }
            }
        }
    }

    private var content: some View {
        List {
            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if store.unreadCount > 0 {
                Section {
                    Button("Mark all read") {
                        Task { await store.markAllRead(using: sessionStore) }
                    }
                    .disabled(store.isLoading)
                }
            }

            let items = store.snapshot?.items ?? []
            if items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No activity",
                        systemImage: "bell.slash",
                        description: Text("Recent workspace notifications will appear here.")
                    )
                }
            } else {
                Section {
                    ForEach(items) { item in
                        activityRow(item)
                    }
                }
            }
        }
        .refreshable {
            await store.refresh(using: sessionStore, limit: 40)
        }
    }

    @ViewBuilder
    private func activityRow(_ item: ActivityItemDTO) -> some View {
        let access = AppRouteAccess(fullAccess: sessionStore.identity?.fullAccess == true)
        let destination = AppRoute(href: item.href ?? "")

        if let destination, destination.isAccessible(access: access) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    open(destination)
                } label: {
                    rowContent(item)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button(primaryActionTitle(for: destination)) {
                        open(destination)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JobWinPalette.primary)

                    if let secondaryRoute = secondaryActionRoute(for: destination),
                       secondaryRoute.isAccessible(access: access) {
                        Button(secondaryActionTitle(for: secondaryRoute)) {
                            open(secondaryRoute)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: ActivityItemDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: item.icon))
                .font(.body.weight(.semibold))
                .foregroundStyle(color(for: item.category))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)
                    if item.unread {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(item.description)
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.createdAtLabel)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func iconName(for icon: String) -> String {
        switch icon {
        case "order": return "clipboard.text"
        case "client": return "person.crop.circle"
        case "booking": return "calendar"
        case "payment": return "creditcard"
        case "estimate": return "doc.text.magnifyingglass"
        case "system": return "gearshape"
        default: return "bell"
        }
    }

    private func color(for category: String) -> Color {
        switch category {
        case "orders": return JobWinPalette.primary
        case "clients": return .blue
        case "bookings": return .orange
        case "payments": return .green
        case "estimates": return .purple
        case "ai_calls": return JobWinPalette.accent
        default: return JobWinPalette.muted
        }
    }

    private func open(_ route: AppRoute) {
        sessionStore.environment.pushService.pendingRoute = route
        dismiss()
    }

    private func primaryActionTitle(for route: AppRoute) -> String {
        switch route {
        case .home:
            return "Home"
        case .calendar:
            return "Calendar"
        case .orders:
            return "Jobs"
        case .tasks:
            return "Tasks"
        case .inbox:
            return "Inbox"
        case .clients:
            return "Clients"
        case .order:
            return "Job"
        case .task:
            return "Task"
        case .client:
            return "Client"
        case .thread:
            return "Thread"
        case let .webPath(path):
            if path.hasPrefix("/billing") {
                return "Billing"
            }
            if path.hasPrefix("/estimates") || path.hasPrefix("/estimate/") {
                return "Estimate"
            }
            if path.hasPrefix("/invoices") || path.hasPrefix("/invoice/") {
                return "Invoice"
            }
            if path.hasPrefix("/settings") {
                return "Settings"
            }
            return "Open"
        }
    }

    private func secondaryActionRoute(for route: AppRoute) -> AppRoute? {
        switch route {
        case .order:
            return .orders
        case .task:
            return .tasks
        case .client:
            return .clients
        case .thread:
            return .inbox
        case let .webPath(path):
            if path.hasPrefix("/estimate/") || path.hasPrefix("/estimates/") {
                return .webPath("/estimates")
            }
            if path.hasPrefix("/invoice/") || path.hasPrefix("/invoices/") {
                return .webPath("/invoices")
            }
            return nil
        default:
            return nil
        }
    }

    private func secondaryActionTitle(for route: AppRoute) -> String {
        switch route {
        case .orders:
            return "All jobs"
        case .tasks:
            return "All tasks"
        case .clients:
            return "All clients"
        case .inbox:
            return "All inbox"
        case let .webPath(path):
            if path == "/estimates" {
                return "All estimates"
            }
            if path == "/invoices" {
                return "All invoices"
            }
            return "Open"
        default:
            return "Open"
        }
    }
}
