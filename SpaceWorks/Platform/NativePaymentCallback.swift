import Foundation

/// Old SDK callbacks may arrive after logout/reset. They cannot complete a later payment attempt.
@MainActor final class NativePaymentCallback {
    private var active: UUID?
    private var completion: ((NativePaymentOutcome) -> Void)?
    var isActive: Bool { active != nil }

    func begin(_ completion: @escaping (NativePaymentOutcome) -> Void) -> UUID? {
        guard active == nil else { return nil }
        let id = UUID()
        active = id
        self.completion = completion
        return id
    }

    @discardableResult func finish(_ result: NativePaymentOutcome, id: UUID, beforeCallback: () -> Void = {}) -> Bool {
        guard active == id else { return false }
        let handler = completion
        active = nil
        completion = nil
        beforeCallback()
        handler?(result)
        return true
    }

    func cancel() {
        if let id = active { finish(.cancelled, id: id) }
    }
}
