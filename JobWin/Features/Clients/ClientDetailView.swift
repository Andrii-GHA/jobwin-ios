import SwiftUI

@Observable
final class ClientDetailModel {
    private let client: APIClient
    private let clientId: String

    var isLoading = false
    var errorMessage: String?
    var noteErrorMessage: String?
    var noteSuccessMessage: String?
    var isSavingNote = false
    var isCalling = false
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var payload: ClientDetailDTO?

    init(client: APIClient, clientId: String) {
        self.client = client
        self.clientId = clientId
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.client(clientId))
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func saveNote(_ body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSavingNote else { return false }

        isSavingNote = true
        noteErrorMessage = nil
        noteSuccessMessage = nil

        defer {
            isSavingNote = false
        }

        do {
            let _: NoteMutationResponseDTO = try await client.post(
                MobileAPI.clientNote(clientId),
                body: NoteRequestBody(body: trimmed)
            )
            noteSuccessMessage = "Note saved."
            await load()
            return true
        } catch {
            noteErrorMessage = error.localizedDescription
            return false
        }
    }

    func startRingOut() async {
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
}

struct ClientDetailView: View {
    let sessionStore: SessionStore
    let clientId: String

    @State private var model: ClientDetailModel?
    @State private var isShowingNoteComposer = false

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing client...")
            }
        }
        .navigationTitle("Client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add note") {
                    isShowingNoteComposer = true
                }
            }
        }
        .sheet(isPresented: $isShowingNoteComposer) {
            if let model {
                NoteComposerView(
                    title: "New note",
                    isSaving: model.isSavingNote,
                    errorMessage: model.noteErrorMessage,
                    onCancel: { isShowingNoteComposer = false },
                    onSave: { body in
                        Task {
                            let saved = await model.saveNote(body)
                            if saved {
                                isShowingNoteComposer = false
                            }
                        }
                    }
                )
            }
        }
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = ClientDetailModel(client: client, clientId: clientId)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: ClientDetailModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading client...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClientHeroCard(client: payload.client)

                    if let noteSuccessMessage = model.noteSuccessMessage {
                        Text(noteSuccessMessage)
                            .font(.footnote)
                            .foregroundStyle(JobWinPalette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DetailSection(title: "Actions") {
                        Button(model.isCalling ? "Calling..." : "Call client") {
                            Task { await model.startRingOut() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JobWinPalette.primary)
                        .disabled(model.isCalling)

                        if let phone = JobWinFormatting.normalizedText(payload.client.primaryPhone) {
                            Button("Text client") {
                                MessageRouting.openText(to: phone)
                            }
                            .buttonStyle(.bordered)
                        }

                        if let address = JobWinFormatting.normalizedText(payload.client.address) {
                            Button("Navigate") {
                                MapRouting.openDirections(to: address)
                            }
                            .buttonStyle(.bordered)
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
                    }

                    if let nextBestAction = JobWinFormatting.normalizedText(payload.client.nextBestAction) {
                        DetailSection(title: "Next best action") {
                            Text(nextBestAction)
                                .foregroundStyle(JobWinPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let jobDescription = JobWinFormatting.normalizedText(payload.client.jobDescription) {
                        DetailSection(title: "Job description") {
                            Text(jobDescription)
                                .foregroundStyle(JobWinPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let thread = payload.recentThread {
                        DetailSection(title: "Recent thread") {
                            NavigationLink {
                                InboxThreadDetailView(sessionStore: sessionStore, threadId: thread.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    DetailLine(title: thread.title, subtitle: thread.lastPreview)
                                    DetailLine(
                                        title: JobWinFormatting.displayDateTime(thread.lastAt) ?? thread.lastAt,
                                        subtitle: JobWinFormatting.bulletJoin(
                                            thread.unread ? "Unread" : nil,
                                            thread.needsFollowUp ? "Needs follow-up" : nil,
                                            thread.hasTransfer ? "Transferred" : nil
                                        )
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !payload.recentOrders.isEmpty {
                        DetailSection(title: "Recent orders") {
                            ForEach(payload.recentOrders) { order in
                                NavigationLink {
                                    OrderDetailView(sessionStore: sessionStore, orderId: order.id)
                                } label: {
                                    DetailLine(
                                        title: order.title,
                                        subtitle: JobWinFormatting.bulletJoin(
                                            order.clientName,
                                            JobWinFormatting.displayStatus(order.status),
                                            JobWinFormatting.displayDateTime(order.startsAt)
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !payload.recentTasks.isEmpty {
                        DetailSection(title: "Recent tasks") {
                            ForEach(payload.recentTasks) { task in
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
                            }
                        }
                    }

                    if !payload.recentCallSummaries.isEmpty {
                        DetailSection(title: "Call summaries") {
                            ForEach(payload.recentCallSummaries) { summary in
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
            ErrorStateView(message: "Client data is unavailable.") {
                Task { await model.load() }
            }
        }
    }
}

private struct ClientHeroCard: View {
    let client: ClientDetailClientDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(client.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)

                    if let title = JobWinFormatting.normalizedText(client.title) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(JobWinPalette.muted)
                    }
                }

                Spacer()

                StatusBadge(text: JobWinFormatting.displayStatus(client.status), color: JobWinPalette.primary)
            }

            DetailLine(title: client.primaryPhone ?? "No phone", subtitle: client.primaryEmail)

            if let metadata = JobWinFormatting.bulletJoin(
                client.source.map(JobWinFormatting.displayStatus),
                JobWinFormatting.displayDateTime(client.lastActivityAt)
            ) {
                DetailLine(title: "Activity", subtitle: metadata)
            }

            if let address = JobWinFormatting.normalizedText(client.address) {
                DetailLine(title: "Address", subtitle: address)
            }
        }
        .jobWinCard()
    }
}
