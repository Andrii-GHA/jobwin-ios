import AVFoundation
import SwiftUI
import UIKit

struct JobNoteDraftInput: Hashable {
    let title: String?
    let body: String
    let media: RecordedJobNoteMedia
}

struct JobVoiceNoteComposerView: View {
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (JobNoteDraftInput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body = ""
    @State private var recorder = JobVoiceNoteRecorder()
    @State private var selectedMedia: RecordedJobNoteMedia?
    @State private var pickerSource: JobVideoPickerSource?
    @State private var isShowingVideoSourceOptions = false
    @State private var localErrorMessage: String?

    var bodyView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Field note")
                    .font(.headline)
                    .foregroundStyle(JobWinPalette.ink)

                Text("Capture audio or video about completed work, materials to buy, and anything that may later become a task or estimate.")
                    .font(.subheadline)
                    .foregroundStyle(JobWinPalette.muted)

                TextField("Short title (optional)", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(JobWinPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(JobWinPalette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional typed context")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)

                    TextEditor(text: $body)
                        .frame(minHeight: 140)
                        .padding(12)
                        .background(JobWinPalette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(JobWinPalette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                mediaSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let localErrorMessage {
                    Text(localErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let recorderError = recorder.errorMessage {
                    Text(recorderError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cleanupAndDismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        guard let selectedMedia else { return }
                        onSave(
                            JobNoteDraftInput(
                                title: normalizedText(title),
                                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                                media: selectedMedia
                            )
                        )
                    }
                    .disabled(isSaving || selectedMedia == nil || recorder.isRecording)
                }
            }
        }
        .confirmationDialog(
            "Add video",
            isPresented: $isShowingVideoSourceOptions,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Record video") {
                    pickerSource = .camera
                }
            }

            if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                Button("Choose video") {
                    pickerSource = .photoLibrary
                }
            }
        } message: {
            Text("Attach a short video note from the camera or library.")
        }
        .sheet(item: $pickerSource) { source in
            JobVideoPicker(source: source) { result in
                handlePickedVideo(result)
            }
        }
    }

    var body: some View {
        bodyView
    }

    @ViewBuilder
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio or video")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JobWinPalette.ink)

            if recorder.isRecording {
                DetailLine(
                    title: "Recording audio",
                    subtitle: "Elapsed: \(formattedDuration(recorder.elapsedSeconds))"
                )
            } else if let selectedMedia {
                DetailLine(
                    title: selectedMedia.mediaKind == .video ? "Video ready" : "Audio ready",
                    subtitle: mediaSummary(for: selectedMedia)
                )
            } else {
                DetailLine(
                    title: "No media yet",
                    subtitle: "Record audio or attach a video before saving the note."
                )
            }

            HStack(spacing: 12) {
                Button(recorder.isRecording ? "Stop audio" : "Record audio") {
                    Task {
                        localErrorMessage = nil
                        if recorder.isRecording {
                            selectedMedia = await recorder.stopRecording()
                        } else {
                            deleteSelectedMediaIfNeeded()
                            selectedMedia = nil
                            _ = await recorder.startRecording()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : JobWinPalette.primary)
                .disabled(isSaving)

                Button("Add video") {
                    localErrorMessage = nil
                    isShowingVideoSourceOptions = true
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || recorder.isRecording || !hasAvailableVideoSource)

                if recorder.isRecording || selectedMedia != nil {
                    Button("Discard") {
                        deleteSelectedMediaIfNeeded()
                        selectedMedia = nil
                        localErrorMessage = nil
                        recorder.discardRecording()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }
            }
        }
        .jobWinCard()
    }

    private var hasAvailableVideoSource: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) ||
        UIImagePickerController.isSourceTypeAvailable(.photoLibrary)
    }

    private func cleanupAndDismiss() {
        if recorder.isRecording || selectedMedia != nil {
            deleteSelectedMediaIfNeeded()
            selectedMedia = nil
            recorder.discardRecording()
        }
        dismiss()
    }

    private func deleteSelectedMediaIfNeeded() {
        guard let selectedMedia else { return }
        try? FileManager.default.removeItem(at: selectedMedia.fileURL)
    }

    private func normalizedText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func mediaSummary(for media: RecordedJobNoteMedia) -> String {
        let label = media.mediaKind == .video ? "Video" : "Audio"
        return "\(label) - \(formattedDuration(media.durationSeconds)) - \(ByteCountFormatter.string(fromByteCount: Int64(media.sizeBytes), countStyle: .file))"
    }

    private func handlePickedVideo(_ result: Result<URL, Error>) {
        switch result {
        case let .success(sourceURL):
            do {
                localErrorMessage = nil
                deleteSelectedMediaIfNeeded()
                recorder.discardRecording()
                selectedMedia = try prepareVideoMedia(from: sourceURL)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        case let .failure(error):
            localErrorMessage = error.localizedDescription
        }
    }

    private func prepareVideoMedia(from sourceURL: URL) throws -> RecordedJobNoteMedia {
        let destinationURL = try makePersistedMediaURL(extension: preferredVideoExtension(from: sourceURL))
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let sizeBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let asset = AVURLAsset(url: destinationURL)
        let seconds = asset.duration.seconds.isFinite ? Int(round(asset.duration.seconds)) : 0

        return RecordedJobNoteMedia(
            fileURL: destinationURL,
            mediaKind: .video,
            mimeType: mimeType(for: destinationURL),
            sizeBytes: sizeBytes,
            durationSeconds: max(seconds, 1)
        )
    }

    private func preferredVideoExtension(from url: URL) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        default:
            return "video/mp4"
        }
    }

    private func makePersistedMediaURL(extension fileExtension: String) throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("JobVoiceNotes/Media", isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)", isDirectory: false)
    }
}
