import AVFoundation
import SwiftUI
import VisionKit

/// Camera output is an opaque value for server-side resolution, never an automatically opened URL.
struct NativeQRScanner: View {
    let title: String
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manual = ""
    @State private var cameraReady = false
    @State private var useDataScanner = false
    @State private var submitted = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Scan the QR code, then review the details before confirming.")
                        .foregroundStyle(Color.swMuted)
                    if cameraReady {
                        Group {
                            if useDataScanner {
                                ScannerCamera(onScan: complete, onUnavailable: cameraUnavailable)
                            } else {
                                MetadataCamera(onScan: complete, onUnavailable: cameraUnavailable)
                            }
                        }
                        .frame(minHeight: 280, idealHeight: 360, maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("QR code camera")
                    }
                    if let message {
                        Label(message, systemImage: "camera")
                            .foregroundStyle(Color.swMuted)
                    }
                    Text("Enter code manually").font(.headline)
                    TextField("Code", text: $manual)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
                        .accessibilityIdentifier("scanner-manual-code")
                        .submitLabel(.go).onSubmit { complete(manual) }
                    Button { complete(manual) } label: {
                        Text("Review code").frame(minHeight: 48)
                    }
                        .buttonStyle(.borderedProminent).tint(Color.swAccent)
                        .foregroundStyle(Color.swOnAccent)
                        .disabled(manual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("scanner-review")
                }.padding(24).frame(maxWidth: 640)
            }
            .frame(maxWidth: .infinity).background(Color.swBg).foregroundStyle(Color.swInk)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await prepareCamera() }
        }
    }

    private func prepareCamera() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            message = "Camera scanning is unavailable on this device. Enter the code below."
            return
        }
        var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        useDataScanner = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        cameraReady = allowed
        if !cameraReady { message = "Camera access is unavailable. Enter the code below, or allow Camera in Settings." }
    }

    private func cameraUnavailable() {
        cameraReady = false
        message = "Camera scanning is unavailable. Enter the code below."
    }

    private func complete(_ value: String) {
        guard !submitted else { return }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 2048,
              code.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            message = "Enter a valid code and try again."
            return
        }
        submitted = true
        onScan(code)
        dismiss()
    }
}

private struct ScannerCamera: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onUnavailable: onUnavailable) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch { DispatchQueue.main.async { context.coordinator.onUnavailable() } }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onUnavailable = onUnavailable
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        scanner.delegate = nil
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        var onUnavailable: () -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 2048,
                   value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                    delivered = true
                    dataScanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            dataScanner.stopScanning()
            onUnavailable()
        }
    }
}
