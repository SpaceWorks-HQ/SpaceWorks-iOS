import QuickLook
import SwiftUI
import UIKit

struct NativeDocumentPreview: UIViewControllerRepresentable {
    let file: NativeDocumentFile
    func makeCoordinator() -> Coordinator { Coordinator(file: file) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.file.id != file.id {
            context.coordinator.file = file
            controller.reloadData()
        }
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var file: NativeDocumentFile
        init(file: NativeDocumentFile) { self.file = file }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { file.url as NSURL }
    }
}

/// Present with a native sheet so the system supplies the appropriate iPad presentation anchor.
struct NativeDocumentShare: UIViewControllerRepresentable {
    let file: NativeDocumentFile
    func makeCoordinator() -> Coordinator { Coordinator(file: file) }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    final class Coordinator {
        let file: NativeDocumentFile
        init(file: NativeDocumentFile) { self.file = file }
    }
}
