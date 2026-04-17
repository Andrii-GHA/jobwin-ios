import SwiftUI

struct JobVoiceNoteDraftInput: Hashable {
    let title: String?
    let body: String
    let recording: RecordedJobVoiceNote
}

struct JobVoiceNoteComposerView: View {
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (JobVoiceNoteDraftInput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body = ""
    @State private var recorder = JobVoiceNoteRecorder()
    @State private var recordedNote: RecordedJobVoiceNote?

    var bodyView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voice note")
                    .font(.headline)
                    .foregroundStyle(JobWinPalette.ink)

                Text("Record what was done, what should be bought, or anything that later needs to become a task or estimate.")
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

                recorderSection

                if let errorMessage {
                    Text(errorMessage)
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
            .navigationTitle("New voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cleanupAndDismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        guard let recordedNote else { return }
                        onSave(
                            JobVoiceNoteDraftInput(
                                title: normalizedText(title),
                                body: body.trimmingCharacters(in: .whitespacesAndNewlines),
                                recording: recordedNote
                            )
                        )
                    }
                    .disabled(isSaving || recordedNote == nil || recorder.isRecording)
                }
            }
        }
    }

    var body: some View {
        bodyView
    }

    @ViewBuilder
    private var recorderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JobWinPalette.ink)

            if recorder.isRecording {
                DetailLine(
                    title: "Recording in progress",
                    subtitle: "Elapsed: \(formattedDuration(recorder.elapsedSeconds))"
                )
            } else if let recordedNote {
                DetailLine(
                    title: "Recording ready",
                    subtitle: "\(formattedDuration(recordedNote.durationSeconds)) - \(ByteCountFormatter.string(fromByteCount: Int64(recordedNote.sizeBytes), countStyle: .file))"
                )
            } else {
                DetailLine(title: "No recording yet", subtitle: "Tap record to capture the note.")
            }

            HStack(spacing: 12) {
                Button(recorder.isRecording ? "Stop recording" : "Start recording") {
                    Task {
                        if recorder.isRecording {
                            recordedNote = await recorder.stopRecording()
                        } else {
                            deleteRecordedFileIfNeeded()
                            recordedNote = nil
                            _ = await recorder.startRecording()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : JobWinPalette.primary)
                .disabled(isSaving)

                if recorder.isRecording || recordedNote != nil {
                    Button("Discard") {
                        deleteRecordedFileIfNeeded()
                        recordedNote = nil
                        recorder.discardRecording()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }
            }
        }
        .jobWinCard()
    }

    private func cleanupAndDismiss() {
        if recorder.isRecording || recordedNote != nil {
            deleteRecordedFileIfNeeded()
            recordedNote = nil
            recorder.discardRecording()
        }
        dismiss()
    }

    private func deleteRecordedFileIfNeeded() {
        guard let recordedNote else { return }
        try? FileManager.default.removeItem(at: recordedNote.fileURL)
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
}

