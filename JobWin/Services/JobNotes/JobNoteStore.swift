import Foundation
import Observation

enum JobVoiceNoteUploadStatus: String, Codable, CaseIterable {
    case pending
    case uploading
    case uploaded
    case failed
}

struct JobVoiceNoteLocalRecord: Codable, Identifiable, Hashable {
    let id: String
    var remoteId: String?
    var workspaceId: String?
    var userId: String?
    var orderId: String
    var clientId: String?
    var title: String?
    var body: String
    var transcript: String?
    var summary: String?
    var localFilePath: String
    var mimeType: String?
    var sizeBytes: Int?
    var durationSeconds: Int?
    var uploadStatus: JobVoiceNoteUploadStatus
    var lastErrorMessage: String?
    var convertedEstimateDraftId: String?
    var convertedTaskId: String?
    var createdAt: Date
    var updatedAt: Date
}

@MainActor
@Observable
final class JobNoteStore {
    private static let storageDirectoryName = "JobVoiceNotes"
    private static let storageFileName = "notes.json"

    var notes: [JobVoiceNoteLocalRecord] = []
    var lastErrorMessage: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        loadFromDisk()
    }

    func scopedNotes(for sessionStore: SessionStore, orderId: String) -> [JobVoiceNoteLocalRecord] {
        guard let identity = sessionStore.identity else {
            return notes
                .filter { $0.orderId == orderId }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        return notes
            .filter { note in
                let workspaceMatches = note.workspaceId == nil || note.workspaceId == identity.workspaceId
                let userMatches = note.userId == nil || note.userId == identity.userId
                return workspaceMatches && userMatches && note.orderId == orderId
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func scopedNotes(workspaceId: String?, userId: String?, orderId: String) -> [JobVoiceNoteLocalRecord] {
        notes
            .filter { note in
                let workspaceMatches = workspaceId == nil || note.workspaceId == nil || note.workspaceId == workspaceId
                let userMatches = userId == nil || note.userId == nil || note.userId == userId
                return workspaceMatches && userMatches && note.orderId == orderId
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func pendingOrRetryableNotes(for sessionStore: SessionStore, orderId: String) -> [JobVoiceNoteLocalRecord] {
        scopedNotes(for: sessionStore, orderId: orderId).filter { note in
            note.remoteId == nil || note.uploadStatus != .uploaded
        }
    }

    func pendingOrRetryableNotes(workspaceId: String?, userId: String?, orderId: String) -> [JobVoiceNoteLocalRecord] {
        scopedNotes(workspaceId: workspaceId, userId: userId, orderId: orderId).filter { note in
            note.remoteId == nil || note.uploadStatus != .uploaded
        }
    }

    func note(withId localId: String) -> JobVoiceNoteLocalRecord? {
        notes.first(where: { $0.id == localId })
    }

    @discardableResult
    func createPendingNote(
        using sessionStore: SessionStore,
        orderId: String,
        clientId: String? = nil,
        title: String? = nil,
        body: String = "",
        localFilePath: String,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        durationSeconds: Int? = nil
    ) -> JobVoiceNoteLocalRecord {
        let identity = sessionStore.identity
        let note = JobVoiceNoteLocalRecord(
            id: UUID().uuidString,
            remoteId: nil,
            workspaceId: identity?.workspaceId,
            userId: identity?.userId,
            orderId: orderId,
            clientId: clientId,
            title: normalizedText(title),
            body: body,
            transcript: nil,
            summary: nil,
            localFilePath: localFilePath,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            durationSeconds: durationSeconds,
            uploadStatus: .pending,
            lastErrorMessage: nil,
            convertedEstimateDraftId: nil,
            convertedTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        notes.append(note)
        persist()
        return note
    }

    @discardableResult
    func createPendingNote(
        workspaceId: String?,
        userId: String?,
        orderId: String,
        clientId: String? = nil,
        title: String? = nil,
        body: String = "",
        localFilePath: String,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        durationSeconds: Int? = nil
    ) -> JobVoiceNoteLocalRecord {
        let note = JobVoiceNoteLocalRecord(
            id: UUID().uuidString,
            remoteId: nil,
            workspaceId: workspaceId,
            userId: userId,
            orderId: orderId,
            clientId: clientId,
            title: normalizedText(title),
            body: body,
            transcript: nil,
            summary: nil,
            localFilePath: localFilePath,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            durationSeconds: durationSeconds,
            uploadStatus: .pending,
            lastErrorMessage: nil,
            convertedEstimateDraftId: nil,
            convertedTaskId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        notes.append(note)
        persist()
        return note
    }

    func updateNote(_ localId: String, mutate: (inout JobVoiceNoteLocalRecord) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == localId }) else { return }
        mutate(&notes[index])
        notes[index].updatedAt = Date()
        persist()
    }

    func bindRemoteNote(localId: String, remoteNote: JobNoteDTO) {
        guard let index = notes.firstIndex(where: { $0.id == localId }) else { return }

        notes[index].remoteId = remoteNote.id
        notes[index].clientId = remoteNote.clientId
        notes[index].title = remoteNote.title
        notes[index].body = remoteNote.body ?? notes[index].body
        notes[index].transcript = remoteNote.transcript
        notes[index].summary = remoteNote.summary
        notes[index].uploadStatus = .uploaded
        notes[index].lastErrorMessage = nil
        notes[index].convertedEstimateDraftId = remoteNote.convertedEstimateDraftId
        notes[index].convertedTaskId = remoteNote.convertedTaskId
        notes[index].updatedAt = Date()
        persist()
    }

    func markUploading(localId: String) {
        updateNote(localId) { note in
            note.uploadStatus = .uploading
            note.lastErrorMessage = nil
        }
    }

    func markUploadFailed(localId: String, errorMessage: String) {
        updateNote(localId) { note in
            note.uploadStatus = .failed
            note.lastErrorMessage = errorMessage
        }
    }

    func updateConversion(remoteId: String, estimateDraftId: String? = nil, taskId: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.remoteId == remoteId }) else { return }
        if let estimateDraftId {
            notes[index].convertedEstimateDraftId = estimateDraftId
        }
        if let taskId {
            notes[index].convertedTaskId = taskId
        }
        notes[index].updatedAt = Date()
        persist()
    }

    func clear() {
        notes = []
        persist()
    }

    private func loadFromDisk() {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                notes = []
                lastErrorMessage = nil
                return
            }

            let data = try Data(contentsOf: url)
            notes = try decoder.decode([JobVoiceNoteLocalRecord].self, from: data)
            lastErrorMessage = nil
        } catch {
            notes = []
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            let url = try storageURL()
            let data = try encoder.encode(notes)
            try data.write(to: url, options: [.atomic])
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func storageURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent(Self.storageFileName, isDirectory: false)
    }

    private func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
