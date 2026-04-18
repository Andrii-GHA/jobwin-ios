import AVFoundation
import Foundation
import Observation

struct RecordedJobNoteMedia: Hashable {
    let fileURL: URL
    let mediaKind: JobNoteMediaKind
    let mimeType: String
    let sizeBytes: Int
    let durationSeconds: Int
}

@MainActor
@Observable
final class JobVoiceNoteRecorder: NSObject {
    var isRecording = false
    var elapsedSeconds = 0
    var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var timer: Timer?

    func startRecording() async -> Bool {
        errorMessage = nil

        let granted = await requestPermission()
        guard granted else {
            errorMessage = "Microphone access is required to record a voice note."
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let recordingURL = try makeRecordingURL()
            let recorder = try AVAudioRecorder(url: recordingURL, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.isMeteringEnabled = false
            recorder.prepareToRecord()

            guard recorder.record() else {
                errorMessage = "Could not start recording."
                return false
            }

            audioRecorder = recorder
            activeRecordingURL = recordingURL
            elapsedSeconds = 0
            isRecording = true
            startTimer()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func stopRecording() async -> RecordedJobNoteMedia? {
        guard isRecording else { return nil }

        stopTimer()
        audioRecorder?.stop()
        isRecording = false

        guard let recordingURL = activeRecordingURL else {
            errorMessage = "Recorded file is missing."
            return nil
        }

        let durationSeconds = Int(round(audioRecorder?.currentTime ?? Double(elapsedSeconds)))
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? NSNumber)?
            .intValue ?? 0

        audioRecorder = nil
        activeRecordingURL = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Keep the recorded note even if deactivation fails.
        }

        return RecordedJobNoteMedia(
            fileURL: recordingURL,
            mediaKind: .audio,
            mimeType: "audio/mp4",
            sizeBytes: sizeBytes,
            durationSeconds: max(durationSeconds, 1)
        )
    }

    func discardRecording() {
        stopTimer()
        audioRecorder?.stop()
        if let activeRecordingURL {
            try? FileManager.default.removeItem(at: activeRecordingURL)
        }
        audioRecorder = nil
        activeRecordingURL = nil
        elapsedSeconds = 0
        isRecording = false
        errorMessage = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func makeRecordingURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("JobVoiceNotes/Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent("\(UUID().uuidString).m4a", isDirectory: false)
    }
}
