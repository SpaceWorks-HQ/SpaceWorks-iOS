import AVFoundation
import SwiftUI

/// AVFoundation fallback for older iOS 17 devices without VisionKit DataScanner hardware support.
struct MetadataCamera: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> MetadataScannerController {
        MetadataScannerController(onScan: onScan, onUnavailable: onUnavailable)
    }

    func updateUIViewController(_ controller: MetadataScannerController, context: Context) {
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
    }

    static func dismantleUIViewController(_ controller: MetadataScannerController, coordinator: ()) {
        controller.stop()
    }
}

final class MetadataScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: (String) -> Void
    var onUnavailable: () -> Void
    private let capture = MetadataCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var delivered = false

    init(onScan: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
        self.onScan = onScan
        self.onUnavailable = onUnavailable
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Color.swPanel)
        let preview = AVCaptureVideoPreviewLayer(session: capture.session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.preview = preview
        capture.start(delegate: self) { [weak self] in self?.onUnavailable() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        guard let connection = preview?.connection else { return }
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered else { return }
        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject, code.type == .qr,
                  let value = code.stringValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.utf8.count <= 2048,
                  value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { continue }
            delivered = true
            capture.stop()
            onScan(value)
            return
        }
    }

    func stop() { delivered = true; capture.stop() }
}

/// AVCaptureSession mutation/start/stop are confined to this queue, keeping camera startup off the UI thread.
private final class MetadataCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "org.spaceworks.camera.metadata")

    func start(delegate: AVCaptureMetadataOutputObjectsDelegate, unavailable: @escaping @MainActor () -> Void) {
        queue.async { [self] in
            session.beginConfiguration()
            do {
                guard let device = AVCaptureDevice.default(for: .video) else { throw CaptureFailure.unavailable }
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureMetadataOutput()
                guard session.canAddInput(input) else { throw CaptureFailure.unavailable }
                session.addInput(input)
                guard session.canAddOutput(output) else { throw CaptureFailure.unavailable }
                session.addOutput(output)
                guard output.availableMetadataObjectTypes.contains(.qr) else { throw CaptureFailure.unavailable }
                output.setMetadataObjectsDelegate(delegate, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                session.startRunning()
                if !session.isRunning { Task { @MainActor in unavailable() } }
            } catch {
                session.commitConfiguration()
                Task { @MainActor in unavailable() }
            }
        }
    }

    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
    private enum CaptureFailure: Error { case unavailable }
}
