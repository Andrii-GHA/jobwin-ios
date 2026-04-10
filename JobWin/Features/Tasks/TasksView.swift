import SwiftUI

@Observable
final class TasksModel {
    private let client: APIClient
    private let scope: String
    private let shellMetricsStore: ShellMetricsStore

    var isLoading = false
    var errorMessage: String?
    var actionErrorMessage: String?
    var actionSuccessMessage: String?
    var completingTaskIds: Set<String> = []
    var searchText = ""
    var payload: MobileTasksListDTO?

    init(client: APIClient, scope: String, shellMetricsStore: ShellMetricsStore) {
        self.client = client
        self.scope = scope
        self.shellMetricsStore = shellMetricsStore
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.tasksList(scope: scope))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func completeTask(taskId: String) async {
        if completingTaskIds.contains(taskId) { return }

        completingTaskIds.insert(taskId)
        actionErrorMessage = nil
        actionSuccessMessage = nil

        defer {
            completingTaskIds.remove(taskId)
        }

        do {
            let response: TaskMutationResponseDTO = try await client.post(MobileAPI.taskComplete(taskId))
            guard response.ok else { return }
            payload?.items.removeAll { $0.id == response.task.id }
            actionSuccessMessage = "Task completed."
            await shellMetricsStore.refresh(using: client)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    var filteredItems: [TaskSummaryDTO] {
        let items = payload?.items ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }

        return items.filter { item in
            [
                item.title,
                item.status,
                item.priority,
                item.dueAt ?? "",
            ]
            .joined(separator: "\n")
            .lowercased()
            .contains(query)
        }
    }
}

struct TasksView: View {
    let sessionStore: SessionStore

    @State private var model: TasksModel?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing tasks...")
            }
        }
        .navigationTitle("Tasks")
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                let scope = sessionStore.identity?.fullAccess == true ? "all" : "mine"
                model = TasksModel(
                    client: client,
                    scope: scope,
                    shellMetricsStore: sessionStore.environment.shellMetricsStore
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: TasksModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading tasks...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
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

                let items = model.filteredItems
                if items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No tasks",
                            systemImage: "checklist",
                            description: Text(model.searchText.isEmpty ? "No open tasks right now." : "No tasks match this search.")
                        )
                    }
                } else {
                    Section {
                        ForEach(items) { task in
                            NavigationLink {
                                TaskDetailView(sessionStore: sessionStore, taskId: task.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.title)
                                        .font(.headline)
                                    Text(
                                        JobWinFormatting.bulletJoin(
                                            JobWinFormatting.displayStatus(task.status),
                                            JobWinFormatting.displayStatus(task.priority),
                                            JobWinFormatting.displayDateTime(task.dueAt)
                                        ) ?? JobWinFormatting.displayStatus(task.status)
                                    )
                                    .foregroundStyle(JobWinPalette.muted)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(model.completingTaskIds.contains(task.id) ? "..." : "Done") {
                                    Task { await model.completeTask(taskId: task.id) }
                                }
                                .tint(JobWinPalette.accent)
                                .disabled(model.completingTaskIds.contains(task.id))
                            }
                        }
                    }
                }
            }
            .searchable(text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ), prompt: "Search tasks")
            .refreshable {
                await model.load()
            }
        }
    }
}
