import SwiftUI
import UIKit

/// A separate opaque window covers every app sheet during inactive/background snapshots.
/// It never becomes key, so returning to the app preserves the original responder and draft.
@MainActor final class NativePrivacyShieldController: NSObject {
    private weak var host: UIWindow?
    private(set) var shield: UIWindow?
    private var observing = false

    func attach(to window: UIWindow?) {
        guard host !== window else { return }
        hide()
        host = window
        if window != nil && !observing {
            observing = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(willResign(_:)), name: UIApplication.willResignActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(sceneWillDeactivate(_:)), name: UIScene.willDeactivateNotification, object: nil)
            center.addObserver(self, selector: #selector(didActivate(_:)), name: UIScene.didActivateNotification, object: nil)
            center.addObserver(self, selector: #selector(applicationDidActivate(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        if let scene = window?.windowScene, scene.activationState != .foregroundActive { show() }
    }

    func detach() {
        hide()
        host = nil
        NotificationCenter.default.removeObserver(self)
        observing = false
    }

    @objc private func willResign(_ notification: Notification) { show() }
    @objc private func sceneWillDeactivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === host?.windowScene else { return }
        show()
    }
    @objc private func didActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === host?.windowScene else { return }
        hide()
    }
    @objc private func applicationDidActivate(_ notification: Notification) {
        if host?.windowScene?.activationState == .foregroundActive { hide() }
    }

    private func show() {
        guard shield == nil, let host, let scene = host.windowScene else { return }
        let cover = UIWindow(windowScene: scene)
        cover.frame = host.frame
        cover.windowLevel = .init(rawValue: UIWindow.Level.alert.rawValue + 1)
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(named: "bg") ?? .systemBackground
        controller.view.isOpaque = true
        controller.view.accessibilityIdentifier = "private-app-snapshot"
        controller.view.accessibilityLabel = "Space Works"
        controller.view.accessibilityViewIsModal = true
        cover.rootViewController = controller
        cover.isOpaque = true
        cover.isHidden = false
        // Do not call makeKeyAndVisible: the app's existing key window keeps keyboard ownership.
        cover.layoutIfNeeded()
        shield = cover
    }

    private func hide() {
        shield?.isHidden = true
        shield?.rootViewController = nil
        shield = nil
    }
}

private struct NativePrivacyShield: UIViewRepresentable {
    func makeCoordinator() -> NativePrivacyShieldController { NativePrivacyShieldController() }
    func makeUIView(context: Context) -> PrivacyHostView {
        let view = PrivacyHostView()
        view.controller = context.coordinator
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ uiView: PrivacyHostView, context: Context) { context.coordinator.attach(to: uiView.window) }
    static func dismantleUIView(_ uiView: PrivacyHostView, coordinator: NativePrivacyShieldController) { coordinator.detach() }
}

private final class PrivacyHostView: UIView {
    weak var controller: NativePrivacyShieldController?
    override func didMoveToWindow() { super.didMoveToWindow(); controller?.attach(to: window) }
}

extension View {
    func nativePrivacyShield() -> some View { background(NativePrivacyShield().frame(width: 0, height: 0).accessibilityHidden(true)) }
}
