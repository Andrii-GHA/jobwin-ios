import SwiftUI

@Observable
final class OrdersModel {
    private let client: APIClient

    var isLoading = false
    var errorMessage: String?
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var activeCallOrderId: String?
    var payload: MobileOrdersListDTO?

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.orders)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
}

struct OrdersView: View {
    let sessionStore: SessionStore

    @State private var model: OrdersModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing orders...")
            }
        }
        .navigationTitle("Orders")
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = OrdersModel(client: client)
            }
            await model?.load()
        }
        .searchable(text: $searchText, prompt: "Search orders")
    }

    @ViewBuilder
    private func content(model: OrdersModel) -> some View {
        let canRingOut = sessionStore.identity?.fullAccess == true

        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading orders...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else {
            let items = filteredItems(model.payload?.items ?? [])

            if items.isEmpty {
                ContentUnavailableView(
                    "No matching orders",
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
                        NavigationLink {
                            OrderDetailView(sessionStore: sessionStore, orderId: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                Text(
                                    JobWinFormatting.bulletJoin(
                                        item.clientName,
                                        JobWinFormatting.displayStatus(item.status)
                                    ) ?? item.clientName
                                )
                                .foregroundStyle(JobWinPalette.muted)
                                if let schedule = JobWinFormatting.displayDateTime(item.startsAt) {
                                    Text(schedule)
                                        .font(.footnote)
                                        .foregroundStyle(JobWinPalette.muted)
                                }
                                if let address = item.address {
                                    Text(address)
                                        .font(.footnote)
                                        .foregroundStyle(JobWinPalette.muted)
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

                            if let phone = JobWinFormatting.normalizedText(item.clientPhone) {
                                Button("Text") {
                                    MessageRouting.openText(to: phone)
                                }
                                .tint(.green)
                            }

                            if canRingOut, item.clientId != nil {
                                Button(model.activeCallOrderId == item.id ? "..." : "Call") {
                                    Task { await model.startRingOut(for: item) }
                                }
                                .tint(JobWinPalette.primary)
                                .disabled(model.activeCallOrderId != nil)
                            }
                        }
                    }
                }
                .refreshable {
                    await model.load()
                }
            }
        }
    }

    private func filteredItems(_ items: [OrderSummaryDTO]) -> [OrderSummaryDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        let normalized = query.lowercased()
        return items.filter { item in
            [
                item.title,
                item.orderNumber,
                item.clientName,
                item.status,
                item.technicianName ?? "",
                item.address ?? "",
            ]
            .joined(separator: "\n")
            .lowercased()
            .contains(normalized)
        }
    }
}

