import SwiftUI

@Observable
final class InboxThreadDetailModel {
    private let client: APIClient
    private let threadId: String

    var isLoading = false
    var errorMessage: String?
    var noteErrorMessage: String?
    var noteSuccessMessage: String?
    var isSavingNote = false
    var isCalling = false
    var callErrorMessage: String?
    var callSuccessMessage: String?
    var payload: InboxThreadDetailDTO?

    init(client: APIClient, threadId: String) {
        self.client = client
        self.threadId = threadId
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.inboxThread(threadId))
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
                MobileAPI.inboxThreadNote(threadId),
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
        guard let clientId = payload?.client.id, !clientId.isEmpty else {
            callErrorMessage = "Client phone context is unavailable."
            return
        }
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

struct InboxThreadDetailView: View {
    let sessionStore: SessionStore
    let threadId: String

    @State private var model: InboxThreadDetailModel?
    @State private var isShowingNoteComposer = false

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing thread...")
            }
        }
        .navigationTitle("Thread")
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
                model = InboxThreadDetailModel(client: client, threadId: threadId)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: InboxThreadDetailModel) -> some View {
        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading thread...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThreadHeroCard(payload: payload)

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

                        NavigationLink {
                            ClientDetailView(sessionStore: sessionStore, clientId: payload.client.id)
                        } label: {
                            Text("Open client")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    DetailSection(title: "Timeline") {
                        ForEach(payload.timeline) { item in
                            switch item {
                            case let .message(message):
                                MessageTimelineCard(item: message)
                            case let .call(call):
                                CallTimelineCard(item: call)
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
            ErrorStateView(message: "Thread data is unavailable.") {
                Task { await model.load() }
            }
        }
    }
}

private struct ThreadHeroCard: View {
    let payload: InboxThreadDetailDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.thread.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)
                    Text(JobWinFormatting.displayDateTime(payload.thread.lastAt) ?? payload.thread.lastAt)
                        .font(.footnote)
                        .foregroundStyle(JobWinPalette.muted)
                }

                Spacer()

                if payload.thread.unread {
                    StatusBadge(text: "Unread", color: JobWinPalette.primary)
                }
            }

            DetailLine(
                title: payload.client.displayName,
                subtitle: JobWinFormatting.bulletJoin(payload.client.primaryPhone, payload.client.primaryEmail)
            )

            if let metadata = JobWinFormatting.bulletJoin(
                payload.client.source.map(JobWinFormatting.displayStatus),
                JobWinFormatting.displayStatus(payload.client.status)
            ) {
                DetailLine(title: "Context", subtitle: metadata)
            }

            if let address = JobWinFormatting.normalizedText(payload.client.address) {
                DetailLine(title: "Address", subtitle: address)
            }

            if let nextBestAction = JobWinFormatting.normalizedText(payload.nextBestAction) {
                DetailLine(title: "Next best action", subtitle: nextBestAction)
            }
        }
        .jobWinCard()
    }
}

private struct MessageTimelineCard: View {
    let item: MessageTimelineItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(
                    text: JobWinFormatting.displayStatus(item.direction),
                    color: item.direction.lowercased() == "outbound" ? JobWinPalette.primary : JobWinPalette.accent
                )

                if let label = JobWinFormatting.bulletJoin(
                    item.channel.map(JobWinFormatting.displayStatus),
                    item.messageType.map(JobWinFormatting.displayStatus)
                ) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(JobWinPalette.muted)
                }

                Spacer()

                Text(JobWinFormatting.displayDateTime(item.at) ?? item.at)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }

            Text(item.body)
                .font(.body)
                .foregroundStyle(JobWinPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(JobWinPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(JobWinPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CallTimelineCard: View {
    let item: CallTimelineItemDTO

    var body: some View {
        CallSummaryCard(summary: item.call)
    }
}
