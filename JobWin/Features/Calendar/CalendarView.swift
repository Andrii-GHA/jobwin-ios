import SwiftUI

private enum CalendarPresentationMode: String, CaseIterable, Identifiable {
    case agenda
    case liveMap = "live_map"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agenda:
            return "Agenda"
        case .liveMap:
            return "Live Map"
        }
    }
}

@Observable
final class CalendarModel {
    private let client: APIClient
    private let shellMetricsStore: ShellMetricsStore

    var isLoading = false
    var errorMessage: String?
    var actionErrorMessage: String?
    var actionSuccessMessage: String?
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var activeOrderActionId: String?
    var activeTaskActionId: String?
    var activeCallOrderId: String?
    var payload: MobileCalendarDTO?

    init(client: APIClient, shellMetricsStore: ShellMetricsStore) {
        self.client = client
        self.shellMetricsStore = shellMetricsStore
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.calendar)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func performOrderAction(orderId: String, action: OrderFieldAction) async {
        if activeOrderActionId != nil { return }

        activeOrderActionId = "\(orderId):\(action.rawValue)"
        actionErrorMessage = nil
        actionSuccessMessage = nil

        defer {
            activeOrderActionId = nil
        }

        do {
            let _: OrderFieldEventResponseDTO = try await client.post(MobileAPI.orderField(orderId, action: action.rawValue))
            actionSuccessMessage = action.successMessage
            await load()
            await shellMetricsStore.refresh(using: client)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func startRingOut(for order: OrderSummaryDTO) async {
        guard let leadId = JobWinFormatting.normalizedText(order.clientId) else {
            callErrorMessage = "Client context is unavailable."
            return
        }
        guard activeCallOrderId == nil else { return }

        activeCallOrderId = order.id
        callErrorMessage = nil
        callSuccessMessage = nil

        defer {
            activeCallOrderId = nil
        }

        do {
            let response: RingOutResponseDTO = try await client.post(
                MobileAPI.ringOut,
                body: RingOutRequestBody(leadId: leadId, clientId: nil)
            )
            guard response.ok else { return }
            callSuccessMessage = response.customerPhone.map { "Calling \($0)." } ?? "Ring-out started."
        } catch {
            callErrorMessage = error.localizedDescription
        }
    }

    func completeTask(taskId: String) async {
        if activeTaskActionId != nil { return }

        activeTaskActionId = taskId
        actionErrorMessage = nil
        actionSuccessMessage = nil

        defer {
            activeTaskActionId = nil
        }

        do {
            let response: TaskMutationResponseDTO = try await client.post(MobileAPI.taskComplete(taskId))
            guard response.ok else { return }
            actionSuccessMessage = "Task completed."
            payload?.tasks.removeAll { $0.id == response.task.id }
            await shellMetricsStore.refresh(using: client)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}

struct CalendarView: View {
    let sessionStore: SessionStore

    @State private var model: CalendarModel?
    @State private var presentationMode: CalendarPresentationMode = .agenda

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing calendar...")
            }
        }
        .navigationTitle("Calendar")
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = CalendarModel(client: client, shellMetricsStore: sessionStore.environment.shellMetricsStore)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: CalendarModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading calendar...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            VStack(spacing: 0) {
                Picker("View", selection: $presentationMode) {
                    ForEach(CalendarPresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if presentationMode == .agenda {
                    agendaView(model: model, payload: payload)
                } else {
                    LiveMapView(sessionStore: sessionStore, orders: payload.orders)
                }
            }
        }
    }

    private func agendaView(model: CalendarModel, payload: MobileCalendarDTO) -> some View {
        let canRingOut = sessionStore.identity?.fullAccess == true

        List {
            if let actionSuccessMessage = model.actionSuccessMessage {
                Section {
                    Text(actionSuccessMessage)
                        .font(.footnote)
                        .foregroundStyle(JobWinPalette.accent)
                }
            }

            if let actionErrorMessage = model.actionErrorMessage {
                Section {
                    Text(actionErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let callSuccessMessage = model.callSuccessMessage {
                Section {
                    Text(callSuccessMessage)
                        .font(.footnote)
                        .foregroundStyle(JobWinPalette.accent)
                }
            }

            if let callErrorMessage = model.callErrorMessage {
                Section {
                    Text(callErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Orders") {
                ForEach(payload.orders) { order in
                    NavigationLink {
                        OrderDetailView(sessionStore: sessionStore, orderId: order.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(order.title)
                                .font(.headline)
                            Text(
                                JobWinFormatting.bulletJoin(
                                    order.clientName,
                                    JobWinFormatting.displayDateTime(order.startsAt)
                                ) ?? order.clientName
                            )
                            .foregroundStyle(JobWinPalette.muted)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if let address = JobWinFormatting.normalizedText(order.address) {
                            Button("Navigate") {
                                MapRouting.openDirections(to: address)
                            }
                            .tint(.blue)
                        }

                        if let phone = JobWinFormatting.normalizedText(order.clientPhone) {
                            Button("Text") {
                                MessageRouting.openText(to: phone)
                            }
                            .tint(.green)
                        }

                        if canRingOut, order.clientId != nil {
                            Button(model.activeCallOrderId == order.id ? "..." : "Call") {
                                Task { await model.startRingOut(for: order) }
                            }
                            .tint(JobWinPalette.primary)
                            .disabled(model.activeCallOrderId != nil)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        ForEach([OrderFieldAction.complete, OrderFieldAction.start, OrderFieldAction.arrived], id: \.id) { action in
                            Button(action.title) {
                                Task { await model.performOrderAction(orderId: order.id, action: action) }
                            }
                            .tint(color(for: action))
                            .disabled(model.activeOrderActionId != nil)
                        }
                    }
                }
            }

            if payload.tasksAvailable {
                Section("Tasks") {
                    ForEach(payload.tasks) { task in
                        NavigationLink {
                            TaskDetailView(sessionStore: sessionStore, taskId: task.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.headline)
                                Text(JobWinFormatting.displayStatus(task.priority))
                                    .foregroundStyle(JobWinPalette.muted)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(model.activeTaskActionId == task.id ? "..." : "Done") {
                                Task { await model.completeTask(taskId: task.id) }
                            }
                            .tint(JobWinPalette.accent)
                            .disabled(model.activeTaskActionId != nil)
                        }
                    }
                }
            }
        }
        .refreshable {
            await model.load()
        }
    }

    private func color(for action: OrderFieldAction) -> Color {
        switch action {
        case .arrived:
            return .orange
        case .start:
            return JobWinPalette.primary
        case .complete:
            return JobWinPalette.accent
        }
    }
}
