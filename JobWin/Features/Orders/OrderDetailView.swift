import SwiftUI

@Observable
final class OrderDetailModel {
    private let client: APIClient
    private let orderId: String
    private let shellMetricsStore: ShellMetricsStore

    var isLoading = false
    var errorMessage: String?
    var actionErrorMessage: String?
    var actionSuccessMessage: String?
    var activeAction: String?
    var completingTaskIds: Set<String> = []
    var taskErrorMessage: String?
    var taskSuccessMessage: String?
    var isRescheduling = false
    var rescheduleErrorMessage: String?
    var rescheduleSuccessMessage: String?
    var isCalling = false
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var payload: OrderDetailDTO?

    init(client: APIClient, orderId: String, shellMetricsStore: ShellMetricsStore) {
        self.client = client
        self.orderId = orderId
        self.shellMetricsStore = shellMetricsStore
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.order(orderId))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func performFieldAction(_ action: OrderFieldAction) async {
        if activeAction != nil { return }

        activeAction = action.rawValue
        actionErrorMessage = nil
        actionSuccessMessage = nil

        defer {
            activeAction = nil
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

    func startRingOut(clientId: String) async {
        guard !isCalling else { return }

        isCalling = true
        callErrorMessage = nil
        callSuccessMessage = nil

        defer {
            isCalling = false
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

    func completeTask(taskId: String) async {
        if completingTaskIds.contains(taskId) { return }

        completingTaskIds.insert(taskId)
        taskErrorMessage = nil
        taskSuccessMessage = nil

        defer {
            completingTaskIds.remove(taskId)
        }

        do {
            let response: TaskMutationResponseDTO = try await client.post(MobileAPI.taskComplete(taskId))
            guard response.ok else { return }
            payload?.tasks.removeAll { $0.id == response.task.id }
            taskSuccessMessage = "Task completed."
            await shellMetricsStore.refresh(using: client)
        } catch {
            taskErrorMessage = error.localizedDescription
        }
    }

    func reschedule(startsAt: Date, endsAt: Date) async -> Bool {
        guard !isRescheduling else { return false }

        isRescheduling = true
        rescheduleErrorMessage = nil
        rescheduleSuccessMessage = nil

        defer {
            isRescheduling = false
        }

        do {
            let response: RescheduleResponseDTO = try await client.post(
                MobileAPI.orderReschedule(orderId),
                body: RescheduleRequestBody(
                    startsAt: JobWinFormatting.iso8601String(from: startsAt),
                    endsAt: JobWinFormatting.iso8601String(from: endsAt)
                )
            )
            guard response.ok else { return false }
            rescheduleSuccessMessage = "Order rescheduled."
            await load()
            await shellMetricsStore.refresh(using: client)
            return true
        } catch {
            rescheduleErrorMessage = error.localizedDescription
            return false
        }
    }

    var currentScheduleStart: Date {
        JobWinFormatting.date(from: payload?.order.startsAt) ?? Date()
    }

    var currentScheduleEnd: Date {
        JobWinFormatting.date(from: payload?.order.endsAt) ?? currentScheduleStart.addingTimeInterval(60 * 60)
    }
}

struct OrderDetailView: View {
    let sessionStore: SessionStore
    let orderId: String

    @State private var model: OrderDetailModel?
    @State private var isShowingReschedule = false

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing order...")
            }
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingReschedule) {
            if let model {
                RescheduleOrderView(
                    title: "Reschedule order",
                    initialStart: model.currentScheduleStart,
                    initialEnd: model.currentScheduleEnd,
                    isSaving: model.isRescheduling,
                    errorMessage: model.rescheduleErrorMessage,
                    onCancel: { isShowingReschedule = false },
                    onSave: { startsAt, endsAt in
                        Task {
                            let saved = await model.reschedule(startsAt: startsAt, endsAt: endsAt)
                            if saved {
                                isShowingReschedule = false
                            }
                        }
                    }
                )
            }
        }
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = OrderDetailModel(
                    client: client,
                    orderId: orderId,
                    shellMetricsStore: sessionStore.environment.shellMetricsStore
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: OrderDetailModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading order...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OrderHeroCard(order: payload.order)

                    DetailSection(title: "Actions") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(OrderFieldAction.allCases) { action in
                                Button(model.activeAction == action.rawValue ? "..." : action.title) {
                                    Task { await model.performFieldAction(action) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(JobWinPalette.primary)
                                .disabled(model.activeAction != nil)
                            }
                        }

                        if let client = payload.client {
                            Button(model.isCalling ? "Calling..." : "Call client") {
                                Task { await model.startRingOut(clientId: client.id) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(JobWinPalette.primary)
                            .disabled(model.isCalling)

                            if let phone = JobWinFormatting.normalizedText(client.primaryPhone) {
                                Button("Text client") {
                                    MessageRouting.openText(to: phone)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let address = JobWinFormatting.normalizedText(payload.order.address) {
                            Button("Navigate") {
                                MapRouting.openDirections(to: address)
                            }
                            .buttonStyle(.bordered)
                        }

                        if sessionStore.identity?.fullAccess == true {
                            Button("Reschedule") {
                                isShowingReschedule = true
                            }
                            .buttonStyle(.bordered)
                        }

                        if let actionSuccessMessage = model.actionSuccessMessage {
                            Text(actionSuccessMessage)
                                .font(.footnote)
                                .foregroundStyle(JobWinPalette.accent)
                        }

                        if let actionErrorMessage = model.actionErrorMessage {
                            Text(actionErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let callSuccessMessage = model.callSuccessMessage {
                            Text(callSuccessMessage)
                                .font(.footnote)
                                .foregroundStyle(JobWinPalette.accent)
                        }

                        if let callErrorMessage = model.callErrorMessage {
                            Text(callErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let rescheduleSuccessMessage = model.rescheduleSuccessMessage {
                            Text(rescheduleSuccessMessage)
                                .font(.footnote)
                                .foregroundStyle(JobWinPalette.accent)
                        }

                        if let rescheduleErrorMessage = model.rescheduleErrorMessage {
                            Text(rescheduleErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if let client = payload.client {
                        DetailSection(title: "Client") {
                            if sessionStore.identity?.fullAccess == true {
                                NavigationLink {
                                    ClientDetailView(sessionStore: sessionStore, clientId: client.id)
                                } label: {
                                    DetailLine(
                                        title: client.displayName,
                                        subtitle: JobWinFormatting.bulletJoin(client.primaryPhone, client.primaryEmail)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                DetailLine(
                                    title: client.displayName,
                                    subtitle: JobWinFormatting.bulletJoin(client.primaryPhone, client.primaryEmail)
                                )
                            }
                        }
                    }

                    if !payload.order.serviceDetails.isEmpty {
                        DetailSection(title: "Service details") {
                            ForEach(payload.order.serviceDetails.keys.sorted(), id: \.self) { key in
                                DetailLine(
                                    title: JobWinFormatting.displayStatus(key),
                                    subtitle: JobWinFormatting.normalizedText(payload.order.serviceDetails[key])
                                )
                            }
                        }
                    }

                    if let notes = JobWinFormatting.normalizedText(payload.order.notes) {
                        DetailSection(title: "Notes") {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(JobWinPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !payload.tasks.isEmpty {
                        DetailSection(title: "Tasks") {
                            ForEach(payload.tasks) { task in
                                HStack(alignment: .top, spacing: 12) {
                                    NavigationLink {
                                        TaskDetailView(sessionStore: sessionStore, taskId: task.id)
                                    } label: {
                                        DetailLine(
                                            title: task.title,
                                            subtitle: JobWinFormatting.bulletJoin(
                                                JobWinFormatting.displayStatus(task.status),
                                                JobWinFormatting.displayStatus(task.priority),
                                                JobWinFormatting.displayDateTime(task.dueAt)
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button(model.completingTaskIds.contains(task.id) ? "..." : "Done") {
                                        Task { await model.completeTask(taskId: task.id) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(JobWinPalette.primary)
                                    .disabled(model.completingTaskIds.contains(task.id))
                                }
                            }

                            if let taskSuccessMessage = model.taskSuccessMessage {
                                Text(taskSuccessMessage)
                                    .font(.footnote)
                                    .foregroundStyle(JobWinPalette.accent)
                            }

                            if let taskErrorMessage = model.taskErrorMessage {
                                Text(taskErrorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !payload.callSummaries.isEmpty {
                        DetailSection(title: "Call summaries") {
                            ForEach(payload.callSummaries) { summary in
                                CallSummaryCard(summary: summary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                await model.load()
            }
        } else {
            ErrorStateView(message: "Order data is unavailable.") {
                Task { await model.load() }
            }
        }
    }
}

private struct OrderHeroCard: View {
    let order: OrderDetailOrderDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)
                    Text(order.orderNumber)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(JobWinPalette.muted)
                }

                Spacer()

                StatusBadge(text: JobWinFormatting.displayStatus(order.status), color: JobWinPalette.primary)
            }

            DetailLine(
                title: order.clientName,
                subtitle: JobWinFormatting.bulletJoin(order.technicianName, order.address)
            )

            if let schedule = JobWinFormatting.bulletJoin(
                JobWinFormatting.displayDateTime(order.startsAt),
                JobWinFormatting.displayTime(order.endsAt)
            ) {
                DetailLine(title: "Schedule", subtitle: schedule)
            }

            HStack(spacing: 8) {
                if order.importantMessage {
                    StatusBadge(text: "Important", color: .orange)
                }
                if order.warrantyCallback {
                    StatusBadge(text: "Warranty", color: JobWinPalette.accent)
                }
            }
        }
        .jobWinCard()
    }
}
