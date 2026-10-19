import AVFoundation
import SwiftUI
import UIKit

enum NativeCameraAvailability: Equatable { case ready, denied, restricted, unavailable }

@MainActor enum NativeCameraAccess {
    /// Call only after the visible evidence flow explains why a photo is needed.
    static func request() async throws -> NativeCameraAvailability {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            try Task.checkCancellation()
            return granted ? .ready : .denied
        @unknown default: return .unavailable
        }
    }
}

enum NativePhotoError: Error, Equatable { case invalidImage, tooLarge, unavailable }

enum NativePhotoPreparation {
    /// Re-rendering applies orientation and discards original EXIF/GPS metadata before JPEG encoding.
    /// Caller supplies the actual server upload cap; this helper never invents an upload policy.
    static func jpeg(from image: UIImage, maximumDimension: CGFloat = 1600,
                     maximumBytes: Int = 5 * 1024 * 1024) throws -> Data {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              maximumDimension.isFinite, (256...4096).contains(maximumDimension),
              maximumBytes > 0, maximumBytes <= 20 * 1024 * 1024 else { throw NativePhotoError.invalidImage }
        let ratio = min(1, maximumDimension / max(width, height))
        let size = CGSize(width: max(1, floor(width * ratio)), height: max(1, floor(height * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Flatten transparency onto a neutral photo background, not a theme-dependent tint.
            context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [CGFloat(0.85), 0.7, 0.55, 0.4] {
            if let data = normalized.jpegData(compressionQuality: quality), data.count <= maximumBytes { return data }
        }
        throw NativePhotoError.tooLarge
    }
}

/// Present only after NativeCameraAccess returns .ready. Parent owns dismissal and photo review.
/// No upload, issue/return mutation or automatic evidence confirmation happens in this adapter.
struct NativeEvidenceCamera: UIViewControllerRepresentable {
    var maximumBytes = 5 * 1024 * 1024
    let onPhoto: (Result<Data, NativePhotoError>) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            // Never construct/present the default photo-library picker as a hardware fallback.
            let unavailable = UIViewController()
            DispatchQueue.main.async { context.coordinator.deliver(.failure(.unavailable)) }
            return unavailable
        }
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = ["public.image"]
        return picker
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { context.coordinator.parent = self }
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        (controller as? UIImagePickerController)?.delegate = nil
        coordinator.finished = true
    }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: NativeEvidenceCamera
        var finished = false
        init(parent: NativeEvidenceCamera) { self.parent = parent }
        func deliver(_ result: Result<Data, NativePhotoError>) {
            guard !finished else { return }
            finished = true
            parent.onPhoto(result)
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !finished else { return }
            guard let image = info[.originalImage] as? UIImage else { deliver(.failure(.invalidImage)); return }
            do { deliver(.success(try NativePhotoPreparation.jpeg(from: image, maximumBytes: parent.maximumBytes))) }
            catch let error as NativePhotoError { deliver(.failure(error)) }
            catch { deliver(.failure(.invalidImage)) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !finished else { return }
            finished = true
            parent.onCancel()
        }
    }
}
