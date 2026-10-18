import SwiftUI

#if DEBUG
import UIKit
import OSLog

/// Read-only UI-test diagnostics. Never creates a controller/window or requests orientation.
private struct NativeOrientationDiagnostics: UIViewRepresentable {
    private var enabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--ui-orientation-diagnostics")
    }
    func makeUIView(context: Context) -> OrientationDiagnosticsView {
        let view = OrientationDiagnosticsView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.enabled = enabled
        return view
    }
    func updateUIView(_ uiView: OrientationDiagnosticsView, context: Context) {
        uiView.enabled = enabled
        uiView.scheduleRead(reason: "view-update")
    }
    static func dismantleUIView(_ uiView: OrientationDiagnosticsView, coordinator: ()) {
        uiView.stop()
    }
}

/// Token cleanup is thread-neutral even if UIKit releases the view outside its usual lifecycle.
private final class OrientationObserverBag {
    var tokens: [NSObjectProtocol] = []
    func cancel() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens.removeAll()
    }
    deinit { cancel() }
}

@MainActor private final class OrientationDiagnosticsView: UIView {
    var enabled = false
    private let observers = OrientationObserverBag()
    private var readScheduled = false
    private var readRevision = 0
    private var lastState: Data?
    private static let logger = Logger(subsystem: "org.spaceworks.orientation-diagnostics", category: "orientation")

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        guard enabled, window != nil else { return }
        for name in [UIDevice.orientationDidChangeNotification, UIScene.didActivateNotification,
                     UIScene.willDeactivateNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.read(reason: "notification:" + notification.name.rawValue)
                }
            }
            observers.tokens.append(token)
        }
        scheduleRead(reason: "attached")
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleRead(reason: "layout")
    }
    func stop() {
        readRevision += 1
        readScheduled = false
        observers.cancel()
        lastState = nil
    }
    func scheduleRead(reason: String) {
        guard enabled, let window, !readScheduled else { return }
        let revision = readRevision
        readScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.readRevision == revision else { return }
            self.readScheduled = false
            guard let window, self.window === window else { return }
            self.read(reason: reason)
        }
    }

    private func read(reason: String) {
        guard enabled, let window, let scene = window.windowScene else { return }
        // No view loading: .view is read only when UIKit says it is already loaded.
        var visited = Set<ObjectIdentifier>()
        var remaining = 128
        func controller(_ value: UIViewController, path: String, depth: Int) -> [[String: Any]] {
            guard depth < 12, remaining > 0, visited.insert(ObjectIdentifier(value)).inserted else { return [] }
            remaining -= 1
            var node: [String: Any] = ["path": path, "class": String(describing: type(of: value)),
                                     "supported_mask": value.supportedInterfaceOrientations.rawValue,
                                     "should_autorotate": value.shouldAutorotate,
                                     "view_loaded": value.isViewLoaded]
            if value.isViewLoaded { node["view_frame"] = geometry(value.view.frame) }
            if let tabs = value as? UITabBarController { node["selected_tab_index"] = tabs.selectedIndex }
            if let navigation = value as? UINavigationController {
                node["navigation_depth"] = navigation.viewControllers.count
                node["visible_class"] = navigation.visibleViewController.map { String(describing: type(of: $0)) } ?? "none"
            }
            var rows = [node]
            if let presented = value.presentedViewController {
                rows += controller(presented, path: path + ".presented", depth: depth + 1)
            }
            // Include unselected tabs: container orientation policy may consult their masks.
            for (index, child) in value.children.enumerated() {
                rows += controller(child, path: path + ".child[\(index)]", depth: depth + 1)
            }
            return rows
        }
        let windows: [[String: Any]] = scene.windows.prefix(16).enumerated().map { index, item in
            var row: [String: Any] = ["index": index, "class": String(describing: type(of: item)),
                                     "key": item.isKeyWindow, "hidden": item.isHidden,
                                     "level": item.windowLevel.rawValue, "frame": geometry(item.frame),
                                     "bounds": geometry(item.bounds)]
            row["controllers"] = item.rootViewController.map { controller($0, path: "window[\(index)].root", depth: 0) } ?? []
            return row
        }
        var record: [String: Any] = ["kind": "native-orientation-read-only",
                                    "device_orientation": UIDevice.current.orientation.rawValue,
                                    "device_idiom": UIDevice.current.userInterfaceIdiom.rawValue,
                                    "scene_interface_orientation": scene.interfaceOrientation.rawValue,
                                    "scene_activation": scene.activationState.rawValue,
                                    "application_supported_mask": UIApplication.shared.supportedInterfaceOrientations(for: window).rawValue,
                                    "host_window_frame": geometry(window.frame),
                                    "scene_bounds": geometry(scene.coordinateSpace.bounds),
                                    "screen_bounds": geometry(window.screen.bounds), "windows": windows,
                                    "controller_limit_reached": remaining == 0]
        if #available(iOS 26.0, *) {
            let effective = scene.effectiveGeometry
            record["effective_geometry"] = [
                "interface_orientation": effective.interfaceOrientation.rawValue,
                "coordinate_bounds": geometry(effective.coordinateSpace.bounds),
                "interface_orientation_locked": effective.isInterfaceOrientationLocked,
                "interactively_resizing": effective.isInteractivelyResizing
            ] as [String: Any]
        }
        guard let fingerprint = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        // Keep actual notifications even if policy is unchanged; suppress layout-only duplicates.
        if !reason.hasPrefix("notification:"), fingerprint == lastState { return }
        lastState = fingerprint
        record["event"] = reason
        record["uptime_seconds"] = ProcessInfo.processInfo.systemUptime
        guard let bytes = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let text = String(data: bytes, encoding: .utf8) else { return }
        print("SpaceWorksOrientation " + text)
        Self.logger.notice("SpaceWorksOrientation \(text, privacy: .public)")
    }
    private func geometry(_ frame: CGRect) -> [Any] {
        [frame.minX, frame.minY, frame.width, frame.height].map { value in
            value.isFinite ? Double(value) as Any : "nonfinite" as Any
        }
    }
}
#endif

extension View {
    @ViewBuilder func nativeOrientationDiagnostics() -> some View {
        #if DEBUG
        background(NativeOrientationDiagnostics().frame(width: 0, height: 0).accessibilityHidden(true))
        #else
        self
        #endif
    }
}
