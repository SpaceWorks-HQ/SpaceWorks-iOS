import Foundation
import SpaceWorksAPI

/// Links use a fresh list response; a stale cached charge can never authorize navigation.
@MainActor enum PaymentsLinkDestination {
    static func open(_ id: Int?, state: PaymentsState, navigation: MemberNavigation,
                     isCurrent: () -> Bool) async throws {
        guard isCurrent() else { throw CancellationError() }
        guard state.canRequest, !state.busy else {
            throw APIError(status: state.retryAfter > Date() ? 429 : 0, code: "payment_link_wait",
                detail: "Payments are still loading. Try again in a moment.", retryAfter: state.retryAfter > Date() ? state.retryAfter : nil)
        }
        await state.refresh()
        guard isCurrent() else { throw CancellationError() }
        switch state.load {
        case .ready:
            if let id {
                guard state.record(id) != nil else { throw APIError(status: 404, code: "payment_link_missing", detail: "This charge is no longer available. Refresh your payments.") }
                navigation.open(.payment(id), tab: .profile)
            } else { navigation.open(.payments, tab: .profile) }
        case .failed(let message):
            throw APIError(status: state.retryAfter > Date() ? 429 : 0, code: "payment_link_failed", detail: message, retryAfter: state.retryAfter > Date() ? state.retryAfter : nil)
        default: throw APIError(status: 0, code: "payment_link_wait", detail: "Payments are still loading. Try again in a moment.")
        }
    }
}
