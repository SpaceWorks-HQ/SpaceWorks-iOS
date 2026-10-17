import SwiftUI
import UIKit

/// A fresh, owned operation result. Merely displaying existing state never creates an event.
struct NativeFeedbackEvent: Equatable {
    enum Kind: Equatable { case selection, success, error }
    let id = UUID()
    let kind: Kind
    let activation: UUID?
    @MainActor init(_ kind: Kind) {
        self.kind = kind; activation = NativeFeedbackLifecycle.shared.activation
    }
    @MainActor init(_ kind: Kind, lifecycle: NativeFeedbackLifecycle) {
        self.kind = kind; activation = lifecycle.activation
    }
}

/// Retire feedback before background rendering can be deferred until a later activation.
@MainActor final class NativeFeedbackLifecycle {
    static let shared = NativeFeedbackLifecycle(initiallyActive: UIApplication.shared.applicationState == .active)
    private(set) var activation: UUID?
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    init(initiallyActive: Bool, notifications: NotificationCenter = .default) {
        self.notifications = notifications
        activation = initiallyActive ? UUID() : nil
        observers.append(notifications.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activation = nil }
        })
        observers.append(notifications.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activation = UUID() }
        })
    }
    func accepts(_ event: NativeFeedbackEvent) -> Bool {
        guard let activation else { return false }
        return event.activation == activation
    }
    func stop() {
        for observer in observers { notifications.removeObserver(observer) }
        observers = []; activation = nil
    }
    deinit { for observer in observers { notifications.removeObserver(observer) } }
}

@MainActor enum NativeFeedback {
    static func play(_ kind: NativeFeedbackEvent.Kind) {
        guard UIApplication.shared.applicationState == .active else { return }
        switch kind {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct NativeFeedbackModifier: ViewModifier {
    let event: NativeFeedbackEvent?
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.onChange(of: event) { old, new in
            // No initial emission. The activation check also rejects a callback whose
            // rendering was deferred across background/foreground, even if phase is active.
            guard phase == .active, let new, old != new,
                  NativeFeedbackLifecycle.shared.accepts(new) else { return }
            NativeFeedback.play(new.kind)
        }
    }
}

extension View {
    func nativeFeedback(_ event: NativeFeedbackEvent?) -> some View {
        modifier(NativeFeedbackModifier(event: event))
    }
}
