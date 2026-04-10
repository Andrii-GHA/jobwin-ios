import SwiftUI

private enum InboxFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case followUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .followUp: return "Follow-up"
        }
    }
}

@Observable
final class InboxModel {
    private let client: APIClient

    var isLoading = false
    var errorMessage: String?
    var payload: MobileInboxThreadsDTO?

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.inboxThreads)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct InboxView: View {
    let sessionStore: SessionStore

    @State private var model: InboxModel?
    @State private var searchText = ""
    @State private var selectedFilter: InboxFilter = .all

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing inbox...")
            }
        }
        .navigationTitle("Inbox")
        .searchable(text: $searchText, prompt: "Search inbox")
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = InboxModel(client: client)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: InboxModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading inbox...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
            let items = filteredItems(model.payload?.items ?? [])
            List {
                Section {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(InboxFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No matching threads",
                            systemImage: "magnifyingglass",
                            description: Text("Adjust the filter or search query.")
                        )
                    }
                } else {
                    Section("Threads") {
                        ForEach(items) { item in
                            NavigationLink {
                                InboxThreadDetailView(sessionStore: sessionStore, threadId: item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.title)
                                            .font(.headline)
                                        if item.unread {
                                            Circle()
                                                .fill(JobWinPalette.primary)
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    Text(item.lastPreview)
                                        .foregroundStyle(JobWinPalette.muted)
                                    if let metadata = JobWinFormatting.bulletJoin(
                                        JobWinFormatting.displayDateTime(item.lastAt),
                                        item.needsFollowUp ? "Needs follow-up" : nil,
                                        item.hasTransfer ? "Transferred" : nil
                                    ) {
                                        Text(metadata)
                                            .font(.footnote)
                                            .foregroundStyle(JobWinPalette.muted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .refreshable {
                await model.load()
            }
        }
    }

    private func filteredItems(_ items: [InboxThreadSummaryDTO]) -> [InboxThreadSummaryDTO] {
        let base: [InboxThreadSummaryDTO]
        switch selectedFilter {
        case .all:
            base = items
        case .unread:
            base = items.filter(\.unread)
        case .followUp:
            base = items.filter(\.needsFollowUp)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }

        let normalized = query.lowercased()
        return base.filter { item in
            [
                item.title,
                item.lastPreview,
                item.needsFollowUp ? "needs follow up" : "",
                item.hasTransfer ? "transferred" : "",
                item.unread ? "unread" : "",
            ]
            .joined(separator: "\n")
            .lowercased()
            .contains(normalized)
        }
    }
}
