import SwiftUI

@Observable
final class ClientsModel {
    private let client: APIClient

    var isLoading = false
    var errorMessage: String?
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var activeCallClientId: String?
    var payload: MobileClientsListDTO?

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.clients)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func startRingOut(for clientSummary: ClientSummaryDTO) async {
        guard activeCallClientId == nil else { return }

        activeCallClientId = clientSummary.id
        callErrorMessage = nil
        callSuccessMessage = nil

        defer {
            activeCallClientId = nil
        }

        do {
            let response: RingOutResponseDTO = try await client.post(
                MobileAPI.ringOut,
                body: RingOutRequestBody(leadId: clientSummary.id, clientId: nil)
            )
            guard response.ok else { return }
            callSuccessMessage = response.customerPhone.map { "Calling \($0)." } ?? "Ring-out started."
        } catch {
            callErrorMessage = error.localizedDescription
        }
    }
}

struct ClientsView: View {
    let sessionStore: SessionStore

    @State private var model: ClientsModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing clients...")
            }
        }
        .navigationTitle("Clients")
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = ClientsModel(client: client)
            }
            await model?.load()
        }
        .searchable(text: $searchText, prompt: "Search clients")
    }

    @ViewBuilder
    private func content(model: ClientsModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading clients...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
            let items = filteredItems(model.payload?.items ?? [])

            if items.isEmpty {
                ContentUnavailableView(
                    "No matching clients",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search query.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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

                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                ClientDetailView(sessionStore: sessionStore, clientId: item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.displayName)
                                            .font(.headline)
                                        if item.unreadCount > 0 {
                                            Text("\(item.unreadCount)")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(JobWinPalette.primary.opacity(0.12))
                                                .foregroundStyle(JobWinPalette.primary)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(item.primaryPhone ?? item.primaryEmail ?? JobWinFormatting.displayStatus(item.status))
                                        .foregroundStyle(JobWinPalette.muted)
                                    if let nextBestAction = item.nextBestAction {
                                        Text(nextBestAction)
                                            .font(.footnote)
                                            .foregroundStyle(JobWinPalette.muted)
                                    }
                                    if let lastActivity = JobWinFormatting.displayDateTime(item.lastActivityAt) {
                                        Text(lastActivity)
                                            .font(.footnote)
                                            .foregroundStyle(JobWinPalette.muted)
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                if let threadId = JobWinFormatting.normalizedText(item.threadId) {
                                    NavigationLink {
                                        InboxThreadDetailView(sessionStore: sessionStore, threadId: threadId)
                                    } label: {
                                        Text("Thread")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let latestOrderId = JobWinFormatting.normalizedText(item.latestOrderId) {
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
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if let address = JobWinFormatting.normalizedText(item.address) {
                                Button("Navigate") {
                                    MapRouting.openDirections(to: address)
                                }
                                .tint(.blue)
                            }

                            if let phone = JobWinFormatting.normalizedText(item.primaryPhone) {
                                Button("Text") {
                                    MessageRouting.openText(to: phone)
                                }
                                .tint(.green)
                            }

                            Button(model.activeCallClientId == item.id ? "..." : "Call") {
                                Task { await model.startRingOut(for: item) }
                            }
                            .tint(JobWinPalette.primary)
                            .disabled(model.activeCallClientId != nil)
                        }
                    }
                }
                .refreshable {
                    await model.load()
                }
            }
        }
    }

    private func filteredItems(_ items: [ClientSummaryDTO]) -> [ClientSummaryDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        let normalized = query.lowercased()
        return items.filter { item in
            [
                item.displayName,
                item.primaryPhone ?? "",
                item.primaryEmail ?? "",
                item.source ?? "",
                item.status,
                item.nextBestAction ?? "",
            ]
            .joined(separator: "\n")
            .lowercased()
            .contains(normalized)
        }
    }
}

