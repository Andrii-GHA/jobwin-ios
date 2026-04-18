import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum JobVideoPickerSource: String, Identifiable {
    case camera
    case photoLibrary

    var id: String { rawValue }

    var pickerSourceType: UIImagePickerController.SourceType {
        switch self {
        case .camera:
            return .camera
        case .photoLibrary:
            return .photoLibrary
        }
    }

    var title: String {
        switch self {
        case .camera:
            return "Record video"
        case .photoLibrary:
            return "Choose video"
        }
    }
}

enum JobVideoPickerError: LocalizedError {
    case unavailable
    case missingURL

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Video source is unavailable on this device."
        case .missingURL:
            return "The selected video could not be loaded."
        }
    }
}

struct JobVideoPicker: UIViewControllerRepresentable {
    let source: JobVideoPickerSource
    let onComplete: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = source.pickerSourceType
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        uiViewController.delegate = nil
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onComplete: (Result<URL, Error>) -> Void

        init(onComplete: @escaping (Result<URL, Error>) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let result: Result<URL, Error>
            if let mediaURL = info[.mediaURL] as? URL {
                result = .success(mediaURL)
            } else {
                result = .failure(JobVideoPickerError.missingURL)
            }

            picker.dismiss(animated: true) {
                self.onComplete(result)
            }
        }
    }
}
