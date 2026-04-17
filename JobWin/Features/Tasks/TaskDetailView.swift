import SwiftUI

@Observable
final class TaskDetailModel {
    private let client: APIClient
    private let taskId: String
    private let shellMetricsStore: ShellMetricsStore

    var isLoading = false
    var errorMessage: String?
    var actionErrorMessage: String?
    var actionSuccessMessage: String?
    var isCompleting = false
    var payload: TaskDetailDTO?

    init(client: APIClient, taskId: String, shellMetricsStore: ShellMetricsStore) {
        self.client = client
        self.taskId = taskId
        self.shellMetricsStore = shellMetricsStore
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.task(taskId))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func completeTask() async {
        guard !isCompleting else { return }

        isCompleting = true
        actionErrorMessage = nil
        actionSuccessMessage = nil

        defer {
            isCompleting = false
        }

        do {
            let response: TaskMutationResponseDTO = try await client.post(MobileAPI.taskComplete(taskId))
            guard response.ok else { return }
            actionSuccessMessage = "Task completed."
            await load()
            await shellMetricsStore.refresh(using: client)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}

struct TaskDetailView: View {
    let sessionStore: SessionStore
    let taskId: String

    @State private var model: TaskDetailModel?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing task...")
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = TaskDetailModel(
                    client: client,
                    taskId: taskId,
                    shellMetricsStore: sessionStore.environment.shellMetricsStore
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: TaskDetailModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading task...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSection(title: "Task") {
                        DetailLine(
                            title: payload.task.title,
                            subtitle: JobWinFormatting.bulletJoin(
                                JobWinFormatting.displayStatus(payload.task.status),
                                JobWinFormatting.displayStatus(payload.task.priority),
                                JobWinFormatting.displayDateTime(payload.task.dueAt)
                            )
                        )

                        if let details = JobWinFormatting.normalizedText(payload.task.details) {
                            Text(details)
                                .font(.body)
                                .foregroundStyle(JobWinPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let completedAt = JobWinFormatting.displayDateTime(payload.task.completedAt) {
                            DetailLine(title: "Completed", subtitle: completedAt)
                        }
                    }

                    DetailSection(title: "Actions") {
                        Button(model.isCompleting ? "Completing..." : "Mark done") {
                            Task { await model.completeTask() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JobWinPalette.accent)
                        .disabled(model.isCompleting || payload.task.status.lowercased() == "done")

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

                    if let recentThread = payload.recentThread, sessionStore.identity?.fullAccess == true {
                        DetailSection(title: "Recent thread") {
                            NavigationLink {
                                InboxThreadDetailView(sessionStore: sessionStore, threadId: recentThread.id)
                            } label: {
                                DetailLine(
                                    title: recentThread.title,
                                    subtitle: JobWinFormatting.bulletJoin(
                                        recentThread.lastPreview,
                                        JobWinFormatting.displayDateTime(recentThread.lastAt)
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !payload.relatedOrders.isEmpty {
                        DetailSection(title: "Related jobs") {
                            ForEach(payload.relatedOrders) { order in
                                NavigationLink {
                                    OrderDetailView(sessionStore: sessionStore, orderId: order.id)
                                } label: {
                                    DetailLine(
                                        title: order.title,
                                        subtitle: JobWinFormatting.bulletJoin(
                                            JobWinFormatting.displayStatus(order.status),
                                            JobWinFormatting.displayDateTime(order.startsAt),
                                            order.technicianName
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
