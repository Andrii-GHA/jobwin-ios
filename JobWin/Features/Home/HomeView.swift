import SwiftUI

@Observable
final class HomeModel {
    private let client: APIClient
    private let shellMetricsStore: ShellMetricsStore

    var isLoading = false
    var errorMessage: String?
    var actionErrorMessage: String?
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var completingTaskIds: Set<String> = []
    var callingClientIds: Set<String> = []
    var payload: HomeOperationsDTO?

    init(client: APIClient, shellMetricsStore: ShellMetricsStore) {
        self.client = client
        self.shellMetricsStore = shellMetricsStore
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.home)
            shellMetricsStore.replace(with: payload)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func completeTask(taskId: String) async {
        if completingTaskIds.contains(taskId) { return }

        completingTaskIds.insert(taskId)
        actionErrorMessage = nil

        defer {
            completingTaskIds.remove(taskId)
        }

        do {
            let response: TaskMutationResponseDTO = try await client.post(MobileAPI.taskComplete(taskId))
            guard response.ok else { return }
            payload?.urgentTasks.removeAll { $0.id == response.task.id }
            shellMetricsStore.replace(with: payload)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func startRingOut(clientId: String) async {
        if callingClientIds.contains(clientId) { return }

        callingClientIds.insert(clientId)
        callErrorMessage = nil
        callSuccessMessage = nil

        defer {
            callingClientIds.remove(clientId)
        }

        do {
            let response: RingOutResponseDTO = try await client.post(
                MobileAPI.ringOut,
                body: RingOutRequestBody(leadId: nil, clientId: clientId)
            )
            guard response.ok else { return }
            callSuccessMessage = response.customerPhone.map { "Calling \($0)." } ?? "Ring-out started."
        } catch {
            callErrorMessage = error.localizedDescription
        }
    }
}

struct HomeView: View {
    let sessionStore: SessionStore

    @State private var model: HomeModel?
    @State private var isShowingSettings = false
    @State private var isShowingActivity = false

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing home...")
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingActivity = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        if sessionStore.environment.activityStore.unreadCount > 0 {
                            Text("\(min(sessionStore.environment.activityStore.unreadCount, 99))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.red)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -10)
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            MobileSettingsView(sessionStore: sessionStore)
        }
        .sheet(isPresented: $isShowingActivity) {
            ActivityCenterView(sessionStore: sessionStore)
        }
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = HomeModel(client: client, shellMetricsStore: sessionStore.environment.shellMetricsStore)
            }
            await model?.load()
            await sessionStore.environment.activityStore.refresh(using: sessionStore, limit: 24)
        }
    }

    @ViewBuilder
    private func content(model: HomeModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading operations...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if let payload = model.payload {
                        HomeMetricGrid(payload: payload)
                        if let actionErrorMessage = model.actionErrorMessage {
                            Text(actionErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let callSuccessMessage = model.callSuccessMessage {
                            Text(callSuccessMessage)
                                .font(.footnote)
                                .foregroundStyle(JobWinPalette.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let callErrorMessage = model.callErrorMessage {
                            Text(callErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HomeOrderSection(sessionStore: sessionStore, items: payload.todayOrders)
                        HomeMissedCallsSection(
                            sessionStore: sessionStore,
                            canOpenInbox: sessionStore.identity?.fullAccess == true,
                            canOpenClients: sessionStore.identity?.fullAccess == true,
                            canCallClients: sessionStore.identity?.fullAccess == true,
                            canTextClients: true,
                            callingClientIds: model.callingClientIds,
                            onCall: { clientId in
                                Task { await model.startRingOut(clientId: clientId) }
                            },
                            items: payload.missedCalls
                        )
                        HomeClientSection(
                            sessionStore: sessionStore,
                            canOpenClients: sessionStore.identity?.fullAccess == true,
                            canOpenInbox: sessionStore.identity?.fullAccess == true,
                            canCallClients: sessionStore.identity?.fullAccess == true,
                            canTextClients: true,
                            title: "Needs follow-up",
                            items: payload.followUpQueue,
                            callingClientIds: model.callingClientIds,
                            onCall: { clientId in
                                Task { await model.startRingOut(clientId: clientId) }
                            }
                        )
                        HomeTaskSection(
                            sessionStore: sessionStore,
                            tasksAvailable: payload.tasksAvailable,
                            items: payload.urgentTasks,
                            completingTaskIds: model.completingTaskIds,
                            onComplete: { taskId in
                                Task { await model.completeTask(taskId: taskId) }
                            }
                        )
                    }
                }
                .padding(16)
            }
            .refreshable {
                await model.load()
            }
        }
    }
}

private struct HomeMetricGrid: View {
    let payload: HomeOperationsDTO

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Today orders", value: "\(payload.todayOrders.count)")
            MetricCard(title: "Unread inbox", value: "\(payload.unreadInboxCount)")
            MetricCard(title: "Missed calls", value: "\(payload.missedCalls.count)")
            MetricCard(title: "Urgent tasks", value: "\(payload.urgentTasks.count)")
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(JobWinPalette.muted)
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(JobWinPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jobWinCard()
    }
}

private struct HomeOrderSection: View {
    let sessionStore: SessionStore
    let items: [OrderSummaryDTO]

    var body: some View {
        HomeSection(title: "Today schedule") {
            if items.isEmpty {
                Text("No work scheduled.")
                    .foregroundStyle(JobWinPalette.muted)
            } else {
                ForEach(items.prefix(4)) { item in
                    HStack(alignment: .top, spacing: 12) {
                        NavigationLink {
                            OrderDetailView(sessionStore: sessionStore, orderId: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.clientName)
                                    .foregroundStyle(JobWinPalette.muted)
                                if let startsAt = JobWinFormatting.displayDateTime(item.startsAt) {
                                    Text(startsAt)
                                        .font(.footnote)
                                        .foregroundStyle(JobWinPalette.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let address = JobWinFormatting.normalizedText(item.address) {
                            Button("Navigate") {
                                MapRouting.openDirections(to: address)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

private struct HomeMissedCallsSection: View {
    let sessionStore: SessionStore
    let canOpenInbox: Bool
    let canOpenClients: Bool
    let canCallClients: Bool
    let canTextClients: Bool
    let callingClientIds: Set<String>
    let onCall: (String) -> Void
    let items: [InboxThreadSummaryDTO]

    var body: some View {
        HomeSection(title: "Missed calls") {
            if items.isEmpty {
                Text("No missed calls.")
                    .foregroundStyle(JobWinPalette.muted)
            } else {
                ForEach(items.prefix(4)) { item in
                    missedCallRow(item: item)
                }
            }
        }
    }

    private func missedCallRow(item: InboxThreadSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if canOpenInbox {
                NavigationLink {
                    InboxThreadDetailView(sessionStore: sessionStore, threadId: item.id)
                } label: {
                    callInfo(item: item)
                }
                .buttonStyle(.plain)
            } else {
                callInfo(item: item)
            }

            if canOpenInbox || canOpenClients || canCallClients || canTextClients {
                HStack(spacing: 10) {
                    if canOpenInbox {
                        NavigationLink {
                            InboxThreadDetailView(sessionStore: sessionStore, threadId: item.id)
                        } label: {
                            Text("Thread")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if canOpenClients, let clientId = JobWinFormatting.normalizedText(item.clientId) {
                        NavigationLink {
                            ClientDetailView(sessionStore: sessionStore, clientId: clientId)
                        } label: {
                            Text("Client")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if canCallClients, let clientId = JobWinFormatting.normalizedText(item.clientId) {
                        Button(callingClientIds.contains(clientId) ? "..." : "Call") {
                            onCall(clientId)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JobWinPalette.primary)
                        .disabled(callingClientIds.contains(clientId))
                    }

                    if canTextClients, let phone = JobWinFormatting.normalizedText(item.clientPhone) {
                        Button("Text") {
                            MessageRouting.openText(to: phone)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let address = JobWinFormatting.normalizedText(item.clientAddress) {
                        Button("Navigate") {
                            MapRouting.openDirections(to: address)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func callInfo(item: InboxThreadSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
            Text(item.lastPreview)
                .foregroundStyle(JobWinPalette.muted)
            Text(JobWinFormatting.displayDateTime(item.lastAt) ?? item.lastAt)
                .font(.footnote)
                .foregroundStyle(JobWinPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeClientSection: View {
    let sessionStore: SessionStore
    let canOpenClients: Bool
    let canOpenInbox: Bool
    let canCallClients: Bool
    let canTextClients: Bool
    let title: String
    let items: [ClientSummaryDTO]
    let callingClientIds: Set<String>
    let onCall: (String) -> Void

    var body: some View {
        HomeSection(title: title) {
            if items.isEmpty {
                Text("Queue is clear.")
                    .foregroundStyle(JobWinPalette.muted)
            } else {
                ForEach(items.prefix(4)) { item in
                    clientRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func clientRow(item: ClientSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if canOpenClients {
                    NavigationLink {
                        ClientDetailView(sessionStore: sessionStore, clientId: item.id)
                    } label: {
                        clientInfo(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    clientInfo(item: item)
                }

                if canCallClients {
                    Button(callingClientIds.contains(item.id) ? "..." : "Call") {
                        onCall(item.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JobWinPalette.primary)
                    .disabled(callingClientIds.contains(item.id))
                }

                if canTextClients, let phone = JobWinFormatting.normalizedText(item.primaryPhone) {
                    Button("Text") {
                        MessageRouting.openText(to: phone)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if canOpenClients || canOpenInbox {
                HStack(spacing: 10) {
                    if canOpenInbox, let threadId = JobWinFormatting.normalizedText(item.threadId) {
                        NavigationLink {
                            InboxThreadDetailView(sessionStore: sessionStore, threadId: threadId)
                        } label: {
                            Text("Thread")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if canOpenClients, let latestOrderId = JobWinFormatting.normalizedText(item.latestOrderId) {
                        NavigationLink {
                            OrderDetailView(sessionStore: sessionStore, orderId: latestOrderId)
                        } label: {
                            Text("Latest order")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clientInfo(item: ClientSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(.headline)
            Text(item.nextBestAction ?? JobWinFormatting.displayStatus(item.status))
                .foregroundStyle(JobWinPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeTaskSection: View {
    let sessionStore: SessionStore
    let tasksAvailable: Bool
    let items: [TaskSummaryDTO]
    let completingTaskIds: Set<String>
    let onComplete: (String) -> Void

    var body: some View {
        HomeSection(title: "Urgent tasks") {
            if tasksAvailable {
                NavigationLink {
                    TasksView(sessionStore: sessionStore)
                } label: {
                    Text("View all tasks")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JobWinPalette.primary)
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                Text("No urgent tasks.")
                    .foregroundStyle(JobWinPalette.muted)
            } else {
                ForEach(items.prefix(4)) { item in
                    HStack(alignment: .top) {
                        NavigationLink {
                            TaskDetailView(sessionStore: sessionStore, taskId: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(JobWinFormatting.displayStatus(item.priority))
                                    .foregroundStyle(JobWinPalette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(completingTaskIds.contains(item.id) ? "..." : "Done") {
                            onComplete(item.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JobWinPalette.primary)
                        .disabled(completingTaskIds.contains(item.id))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(JobWinPalette.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jobWinCard()
    }
}

