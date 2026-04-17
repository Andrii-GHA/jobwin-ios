import SwiftUI

@Observable
final class OrderDetailModel {
    private let client: APIClient
    private let orderId: String
    private let workspaceId: String
    private let userId: String
    private let jobNoteStore: JobNoteStore
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
    var noteErrorMessage: String?
    var noteSuccessMessage: String?
    var isSavingVoiceNote = false
    var convertingEstimateNoteId: String?
    var convertingTaskNoteId: String?
    var payload: OrderDetailDTO?

    init(
        client: APIClient,
        orderId: String,
        workspaceId: String,
        userId: String,
        jobNoteStore: JobNoteStore,
        shellMetricsStore: ShellMetricsStore
    ) {
        self.client = client
        self.orderId = orderId
        self.workspaceId = workspaceId
        self.userId = userId
        self.jobNoteStore = jobNoteStore
        self.shellMetricsStore = shellMetricsStore
    }

    func load(syncPendingNotes: Bool = true) async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            payload = try await client.get(MobileAPI.order(orderId))
            if syncPendingNotes, await syncPendingJobNotes() {
                payload = try await client.get(MobileAPI.order(orderId))
            }
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
            rescheduleSuccessMessage = "Job rescheduled."
            await load()
            await shellMetricsStore.refresh(using: client)
            return true
        } catch {
            rescheduleErrorMessage = error.localizedDescription
            return false
        }
    }

    func saveVoiceNote(_ draft: JobVoiceNoteDraftInput) async -> Bool {
        guard !isSavingVoiceNote else { return false }

        let localNote = await MainActor.run {
            jobNoteStore.createPendingNote(
                workspaceId: workspaceId,
                userId: userId,
                orderId: orderId,
                clientId: payload?.client?.id,
                title: draft.title,
                body: draft.body,
                localFilePath: draft.recording.fileURL.path,
                mimeType: draft.recording.mimeType,
                sizeBytes: draft.recording.sizeBytes,
                durationSeconds: draft.recording.durationSeconds
            )
        }

        noteSuccessMessage = "Voice note stored locally. Syncing..."
        return await uploadLocalJobNote(localNote.id)
    }

    func retryVoiceNote(localId: String) async {
        _ = await uploadLocalJobNote(localId)
    }

    func convertNoteToEstimate(noteId: String) async {
        guard convertingEstimateNoteId == nil else { return }

        convertingEstimateNoteId = noteId
        noteErrorMessage = nil
        noteSuccessMessage = nil

        defer {
            convertingEstimateNoteId = nil
        }

        do {
            let response: JobNoteConversionResponseDTO = try await client.post(
                MobileAPI.orderNoteConvertToEstimate(orderId, noteId: noteId)
            )
            if let estimateDraftId = response.estimateDraftId {
                await MainActor.run {
                    jobNoteStore.updateConversion(remoteId: noteId, estimateDraftId: estimateDraftId)
                }
            }
            noteSuccessMessage = "Estimate draft created from voice note."
            await load(syncPendingNotes: false)
        } catch {
            noteErrorMessage = error.localizedDescription
        }
    }

    func convertNoteToTask(noteId: String) async {
        guard convertingTaskNoteId == nil else { return }

        convertingTaskNoteId = noteId
        noteErrorMessage = nil
        noteSuccessMessage = nil

        defer {
            convertingTaskNoteId = nil
        }

        do {
            let response: JobNoteConversionResponseDTO = try await client.post(
                MobileAPI.orderNoteConvertToTask(orderId, noteId: noteId)
            )
            if let taskId = response.taskId {
                await MainActor.run {
                    jobNoteStore.updateConversion(remoteId: noteId, taskId: taskId)
                }
            }
            noteSuccessMessage = "Task created from voice note."
            await load(syncPendingNotes: false)
            await shellMetricsStore.refresh(using: client)
        } catch {
            noteErrorMessage = error.localizedDescription
        }
    }

    var currentScheduleStart: Date {
        JobWinFormatting.date(from: payload?.order.startsAt) ?? Date()
    }

    var currentScheduleEnd: Date {
        JobWinFormatting.date(from: payload?.order.endsAt) ?? currentScheduleStart.addingTimeInterval(60 * 60)
    }

    private func syncPendingJobNotes() async -> Bool {
        let pendingNotes = await MainActor.run {
            jobNoteStore.pendingOrRetryableNotes(
                workspaceId: workspaceId,
                userId: userId,
                orderId: orderId
            )
        }

        var uploadedAny = false
        for note in pendingNotes where note.uploadStatus != .uploading {
            uploadedAny = await uploadLocalJobNote(note.id) || uploadedAny
        }
        return uploadedAny
    }

    @discardableResult
    private func uploadLocalJobNote(_ localId: String) async -> Bool {
        let localNote = await MainActor.run {
            jobNoteStore.note(withId: localId)
        }
        guard let localNote else { return false }

        let fileURL = URL(fileURLWithPath: localNote.localFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            await MainActor.run {
                jobNoteStore.markUploadFailed(localId: localId, errorMessage: "Recorded audio file is missing.")
            }
            noteErrorMessage = "Recorded audio file is missing."
            return false
        }

        do {
            let data = try Data(contentsOf: fileURL)
            isSavingVoiceNote = true
            noteErrorMessage = nil
            await MainActor.run {
                jobNoteStore.markUploading(localId: localId)
            }

            let response: JobNoteMutationResponseDTO = try await client.postMultipart(
                MobileAPI.orderNotes(orderId),
                fields: [
                    "title": localNote.title ?? "",
                    "body": localNote.body,
                    "durationSeconds": localNote.durationSeconds.map(String.init) ?? "",
                ],
                file: MultipartFormFile(
                    fieldName: "audio",
                    fileName: fileURL.lastPathComponent,
                    mimeType: localNote.mimeType ?? "audio/mp4",
                    data: data
                )
            )

            await MainActor.run {
                jobNoteStore.bindRemoteNote(localId: localId, remoteNote: response.note)
            }
            noteSuccessMessage = "Voice note saved."
            isSavingVoiceNote = false
            return true
        } catch {
            await MainActor.run {
                jobNoteStore.markUploadFailed(localId: localId, errorMessage: error.localizedDescription)
            }
            noteErrorMessage = error.localizedDescription
            isSavingVoiceNote = false
            return false
        }
    }
}

struct OrderDetailView: View {
    let sessionStore: SessionStore
    let orderId: String

    @State private var model: OrderDetailModel?
    @State private var isShowingReschedule = false
    @State private var isShowingVoiceNoteComposer = false

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing job...")
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Notes") {
                    isShowingVoiceNoteComposer = true
                }
            }
        }
        .sheet(isPresented: $isShowingReschedule) {
            if let model {
                RescheduleOrderView(
                    title: "Reschedule job",
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
        .sheet(isPresented: $isShowingVoiceNoteComposer) {
            if let model {
                JobVoiceNoteComposerView(
                    isSaving: model.isSavingVoiceNote,
                    errorMessage: model.noteErrorMessage,
                    onSave: { draft in
                        Task {
                            let saved = await model.saveVoiceNote(draft)
                            if saved {
                                isShowingVoiceNoteComposer = false
                                await model.load(syncPendingNotes: false)
                            }
                        }
                    }
                )
            }
        }
        .task {
            guard
                let client = sessionStore.makeAPIClient(),
                let identity = sessionStore.identity
            else { return }
            if model == nil {
                model = OrderDetailModel(
                    client: client,
                    orderId: orderId,
                    workspaceId: identity.workspaceId,
                    userId: identity.userId,
                    jobNoteStore: sessionStore.environment.jobNoteStore,
                    shellMetricsStore: sessionStore.environment.shellMetricsStore
                )
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: OrderDetailModel) -> some View {
        let canRingOut = sessionStore.identity?.fullAccess == true
        let localPendingNotes = sessionStore.environment.jobNoteStore
            .pendingOrRetryableNotes(for: sessionStore, orderId: orderId)

        if model.isLoading, model.payload == nil {
            LoadingStateView(title: "Loading job...")
        } else if let errorMessage = model.errorMessage, model.payload == nil {
            ErrorStateView(message: errorMessage) {
                Task { await model.load() }
            }
        } else if let payload = model.payload {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OrderHeroCard(order: payload.order)

                    if let noteSuccessMessage = model.noteSuccessMessage {
                        Text(noteSuccessMessage)
                            .font(.footnote)
                            .foregroundStyle(JobWinPalette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let noteErrorMessage = model.noteErrorMessage {
                        Text(noteErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
                            if canRingOut {
                                Button(model.isCalling ? "Calling..." : "Call client") {
                                    Task { await model.startRingOut(clientId: client.id) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(JobWinPalette.primary)
                                .disabled(model.isCalling)
                            }

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

                    DetailSection(title: "Voice notes") {
                        Button("Record voice note") {
                            isShowingVoiceNoteComposer = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JobWinPalette.primary)
                        .disabled(model.isSavingVoiceNote)

                        if localPendingNotes.isEmpty && payload.jobNotes.isEmpty {
                            DetailLine(
                                title: "No voice notes yet",
                                subtitle: "Record work done, materials to buy, or anything that should become a task or estimate."
                            )
                        }

                        ForEach(localPendingNotes) { localNote in
                            LocalJobNoteCard(
                                note: localNote,
                                isRetrying: model.isSavingVoiceNote && (model.noteErrorMessage != nil),
                                onRetry: {
                                    Task { await model.retryVoiceNote(localId: localNote.id) }
                                }
                            )
                        }

                        ForEach(payload.jobNotes) { note in
                            RemoteJobNoteCard(
                                note: note,
                                isConvertingToEstimate: model.convertingEstimateNoteId == note.id,
                                isConvertingToTask: model.convertingTaskNoteId == note.id,
                                onConvertToEstimate: {
                                    Task { await model.convertNoteToEstimate(noteId: note.id) }
                                },
                                onConvertToTask: {
                                    Task { await model.convertNoteToTask(noteId: note.id) }
                                }
                            )
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
            ErrorStateView(message: "Job data is unavailable.") {
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

private struct LocalJobNoteCard: View {
    let note: JobVoiceNoteLocalRecord
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(text: uploadLabel, color: uploadColor)
                Spacer()
                Text(JobWinFormatting.displayDateTime(isoDateString) ?? isoDateString)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }

            if let title = JobWinFormatting.normalizedText(note.title) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(JobWinPalette.ink)
            }

            if let bodyText = JobWinFormatting.normalizedText(note.body) {
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(JobWinPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let subtitle = metadataLabel {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }

            if let error = JobWinFormatting.normalizedText(note.lastErrorMessage) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if note.uploadStatus == .failed {
                Button(isRetrying ? "Retrying..." : "Retry sync", action: onRetry)
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
            }
        }
        .jobWinCard()
    }

    private var isoDateString: String {
        JobWinFormatting.iso8601String(from: note.createdAt)
    }

    private var uploadLabel: String {
        switch note.uploadStatus {
        case .pending: return "Pending sync"
        case .uploading: return "Uploading"
        case .uploaded: return "Saved"
        case .failed: return "Sync failed"
        }
    }

    private var uploadColor: Color {
        switch note.uploadStatus {
        case .pending: return .orange
        case .uploading: return JobWinPalette.primary
        case .uploaded: return JobWinPalette.accent
        case .failed: return .red
        }
    }

    private var metadataLabel: String? {
        JobWinFormatting.bulletJoin(
            note.durationSeconds.map { "\($0 / 60)m \($0 % 60)s" },
            note.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        )
    }
}

private struct RemoteJobNoteCard: View {
    let note: JobNoteDTO
    let isConvertingToEstimate: Bool
    let isConvertingToTask: Bool
    let onConvertToEstimate: () -> Void
    let onConvertToTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(text: "Saved", color: JobWinPalette.accent)
                if note.convertedEstimateDraftId != nil {
                    StatusBadge(text: "Estimate", color: JobWinPalette.primary)
                }
                if note.convertedTaskId != nil {
                    StatusBadge(text: "Task", color: .orange)
                }
                Spacer()
                Text(JobWinFormatting.displayDateTime(note.createdAt) ?? note.createdAt)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }

            if let title = JobWinFormatting.normalizedText(note.title) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(JobWinPalette.ink)
            }

            if let summary = JobWinFormatting.normalizedText(note.summary) {
                Text(summary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(JobWinPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let bodyText = JobWinFormatting.normalizedText(note.body) {
                Text(bodyText)
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let transcriptPreview = transcriptPreview {
                Text(transcriptPreview)
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let metadata = metadataLabel {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(JobWinPalette.muted)
            }

            HStack(spacing: 10) {
                Button(isConvertingToTask ? "Creating task..." : "Convert to task", action: onConvertToTask)
                    .buttonStyle(.bordered)
                    .disabled(isConvertingToTask || note.convertedTaskId != nil)

                Button(
                    isConvertingToEstimate ? "Creating estimate..." : "Convert to estimate",
                    action: onConvertToEstimate
                )
                .buttonStyle(.borderedProminent)
                .tint(JobWinPalette.primary)
                .disabled(isConvertingToEstimate || note.convertedEstimateDraftId != nil)
            }
        }
        .jobWinCard()
    }

    private var transcriptPreview: String? {
        guard let transcript = JobWinFormatting.normalizedText(note.transcript) else { return nil }
        if transcript.count <= 220 {
            return transcript
        }
        return String(transcript.prefix(217)) + "..."
    }

    private var metadataLabel: String? {
        JobWinFormatting.bulletJoin(
            note.durationSeconds.map { "\($0 / 60)m \($0 % 60)s" },
            note.audio?.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
            note.transcriptStatus == .completed ? "Transcript ready" : nil
        )
    }
}
