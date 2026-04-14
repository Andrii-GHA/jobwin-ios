import Foundation
import Observation

struct EstimateDraftLocalMediaRecord: Codable, Identifiable, Hashable {
    let id: String
    var remoteId: String?
    var kind: EstimateDraftMediaKind
    var localFilePath: String
    var mimeType: String?
    var sizeBytes: Int?
    var durationSeconds: Int?
    var uploadStatus: EstimateDraftMediaUploadStatus
    var processingStatus: EstimateDraftAsyncStatus
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date
}

struct EstimateDraftLocalRecord: Codable, Identifiable, Hashable {
    let id: String
    var workspaceId: String?
    var userId: String?
    var remoteDraftId: String?
    var clientId: String?
    var orderId: String?
    var title: String?
    var notes: String
    var status: EstimateDraftStatus
    var analysisStatus: EstimateDraftAsyncStatus
    var pricingStatus: EstimateDraftAsyncStatus
    var localMedia: [EstimateDraftLocalMediaRecord]
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date
}

@MainActor
@Observable
final class EstimateDraftStore {
    private static let storageDirectoryName = "EstimateDrafts"
    private static let storageFileName = "drafts.json"

    var drafts: [EstimateDraftLocalRecord] = []
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

    func scopedDrafts(for sessionStore: SessionStore) -> [EstimateDraftLocalRecord] {
        guard let identity = sessionStore.identity else {
            return drafts.sorted { $0.updatedAt > $1.updatedAt }
        }

        return drafts
            .filter { draft in
                let workspaceMatches = draft.workspaceId == nil || draft.workspaceId == identity.workspaceId
                let userMatches = draft.userId == nil || draft.userId == identity.userId
                return workspaceMatches && userMatches
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createDraft(
        using sessionStore: SessionStore,
        clientId: String? = nil,
        orderId: String? = nil,
        title: String? = nil,
        notes: String = ""
    ) -> EstimateDraftLocalRecord {
        let identity = sessionStore.identity
        let draft = EstimateDraftLocalRecord(
            id: UUID().uuidString,
            workspaceId: identity?.workspaceId,
            userId: identity?.userId,
            remoteDraftId: nil,
            clientId: clientId,
            orderId: orderId,
            title: normalizedText(title),
            notes: notes,
            status: .draft,
            analysisStatus: .idle,
            pricingStatus: .idle,
            localMedia: [],
            lastErrorMessage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        drafts.append(draft)
        persist()
        return draft
    }

    func bindRemoteDraft(
        localDraftId: String,
        remoteDraft: MobileEstimateDraftDTO,
        using sessionStore: SessionStore
    ) {
        guard let index = drafts.firstIndex(where: { $0.id == localDraftId }) else { return }

        drafts[index].workspaceId = sessionStore.identity?.workspaceId ?? drafts[index].workspaceId
        drafts[index].userId = sessionStore.identity?.userId ?? drafts[index].userId
        drafts[index].remoteDraftId = remoteDraft.id
        drafts[index].clientId = remoteDraft.clientId
        drafts[index].orderId = remoteDraft.orderId
        drafts[index].title = remoteDraft.title
        drafts[index].notes = remoteDraft.notes ?? drafts[index].notes
        drafts[index].status = remoteDraft.status
        drafts[index].analysisStatus = remoteDraft.analysisStatus
        drafts[index].pricingStatus = remoteDraft.pricingStatus
        drafts[index].lastErrorMessage = remoteDraft.lastErrorMessage
        drafts[index].updatedAt = Date()
        persist()
    }

    func mergeRemoteDraft(
        _ remoteDraft: MobileEstimateDraftDTO,
        using sessionStore: SessionStore
    ) {
        if let index = drafts.firstIndex(where: { $0.remoteDraftId == remoteDraft.id || $0.id == remoteDraft.id }) {
            drafts[index].workspaceId = sessionStore.identity?.workspaceId ?? drafts[index].workspaceId
            drafts[index].userId = sessionStore.identity?.userId ?? drafts[index].userId
            drafts[index].remoteDraftId = remoteDraft.id
            drafts[index].clientId = remoteDraft.clientId
            drafts[index].orderId = remoteDraft.orderId
            drafts[index].title = remoteDraft.title
            drafts[index].notes = remoteDraft.notes ?? drafts[index].notes
            drafts[index].status = remoteDraft.status
            drafts[index].analysisStatus = remoteDraft.analysisStatus
            drafts[index].pricingStatus = remoteDraft.pricingStatus
            drafts[index].lastErrorMessage = remoteDraft.lastErrorMessage
            drafts[index].updatedAt = Date()
            persist()
            return
        }

        drafts.append(
            EstimateDraftLocalRecord(
                id: remoteDraft.id,
                workspaceId: sessionStore.identity?.workspaceId,
                userId: sessionStore.identity?.userId,
                remoteDraftId: remoteDraft.id,
                clientId: remoteDraft.clientId,
                orderId: remoteDraft.orderId,
                title: remoteDraft.title,
                notes: remoteDraft.notes ?? "",
                status: remoteDraft.status,
                analysisStatus: remoteDraft.analysisStatus,
                pricingStatus: remoteDraft.pricingStatus,
                localMedia: [],
                lastErrorMessage: remoteDraft.lastErrorMessage,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        persist()
    }

    func updateDraft(_ draftId: String, mutate: (inout EstimateDraftLocalRecord) -> Void) {
        guard let index = drafts.firstIndex(where: { $0.id == draftId }) else { return }
        mutate(&drafts[index])
        drafts[index].updatedAt = Date()
        persist()
    }

    @discardableResult
    func appendLocalMedia(
        draftId: String,
        kind: EstimateDraftMediaKind,
        localFilePath: String,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        durationSeconds: Int? = nil
    ) -> EstimateDraftLocalMediaRecord? {
        guard let index = drafts.firstIndex(where: { $0.id == draftId }) else { return nil }

        let media = EstimateDraftLocalMediaRecord(
            id: UUID().uuidString,
            remoteId: nil,
            kind: kind,
            localFilePath: localFilePath,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            durationSeconds: durationSeconds,
            uploadStatus: .pending,
            processingStatus: .idle,
            lastErrorMessage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        drafts[index].localMedia.append(media)
        drafts[index].updatedAt = Date()
        persist()
        return media
    }

    func updateLocalMedia(
        draftId: String,
        mediaId: String,
        remoteId: String? = nil,
        uploadStatus: EstimateDraftMediaUploadStatus? = nil,
        processingStatus: EstimateDraftAsyncStatus? = nil,
        errorMessage: String? = nil
    ) {
        guard let draftIndex = drafts.firstIndex(where: { $0.id == draftId }) else { return }
        guard let mediaIndex = drafts[draftIndex].localMedia.firstIndex(where: { $0.id == mediaId }) else { return }

        if let remoteId {
            drafts[draftIndex].localMedia[mediaIndex].remoteId = remoteId
        }
        if let uploadStatus {
            drafts[draftIndex].localMedia[mediaIndex].uploadStatus = uploadStatus
        }
        if let processingStatus {
            drafts[draftIndex].localMedia[mediaIndex].processingStatus = processingStatus
        }
        if let errorMessage {
            drafts[draftIndex].localMedia[mediaIndex].lastErrorMessage = errorMessage
        }

        drafts[draftIndex].localMedia[mediaIndex].updatedAt = Date()
        drafts[draftIndex].updatedAt = Date()
        persist()
    }

    func deleteDraft(_ draftId: String) {
        drafts.removeAll { $0.id == draftId }
        persist()
    }

    func clear() {
        drafts = []
        persist()
    }

    private func loadFromDisk() {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                drafts = []
                lastErrorMessage = nil
                return
            }

            let data = try Data(contentsOf: url)
            drafts = try decoder.decode([EstimateDraftLocalRecord].self, from: data)
            lastErrorMessage = nil
        } catch {
            drafts = []
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            let url = try storageURL()
            let data = try encoder.encode(drafts)
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
