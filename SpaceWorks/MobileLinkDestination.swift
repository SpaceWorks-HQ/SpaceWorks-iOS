import Foundation
import SpaceWorksAPI

/// A permitted hint still has to resolve against fresh member data before navigation.
@MainActor enum MobileLinkDestination {
    static func open(_ value: MobileLinkRouter.Approved, router: MobileLinkRouter, member: MemberState,
                     navigation: MemberNavigation, drafts: MemberActionDrafts,
                     payment: ((Int?) async throws -> Void)? = nil) async {
        guard router.isCurrent(value) else { return }
        do {
            let destination = value.link.destination
            if value.refetchInbox {
                try available(member, "inbox"); member.unreadOnly = false
                await member.loadInbox(); try ready(member.inboxLoad, deadline: member.deadline("inbox"))
            }
            guard router.isCurrent(value) else { return }
            switch destination {
            case .home, .activity:
                try available(member, "activity"); await member.loadActivity(); try ready(member.activityLoad, deadline: member.deadline("activity"))
            case .inventory:
                try available(member, "inventory"); member.search = ""; member.category = nil
                await member.loadInventory(); try ready(member.inventoryLoad, deadline: member.deadline("inventory"))
            case .product(let id):
                let state = drafts.product(id, repository: member.repository)
                guard (state.retryAfter ?? .distantPast) <= Date(), !state.busy else { throw unavailable(deadline: state.retryAfter) }
                await state.load()
                guard state.product != nil else { throw unavailable(state.error, deadline: state.retryAfter) }
            case .inbox:
                if !value.refetchInbox {
                    try available(member, "inbox"); member.unreadOnly = false
                    await member.loadInbox(); try ready(member.inboxLoad, deadline: member.deadline("inbox"))
                }
            case .bookings, .booking:
                try available(member, "bookings"); await member.loadBookings(); try ready(member.bookingsLoad, deadline: member.deadline("bookings"))
                if case .booking(let token) = destination {
                    var pages = 1
                    while !member.bookings.contains(where: { $0.public_token == token }), member.bookingsHasMore, pages < 100 {
                        guard router.isCurrent(value) else { return }
                        try available(member, "bookings"); await member.loadBookings(more: true); try ready(member.bookingsLoad, deadline: member.deadline("bookings")); pages += 1
                    }
                    guard member.bookings.contains(where: { $0.public_token == token }) else { throw missing }
                }
            case .events, .event:
                try available(member, "events"); await member.loadEvents(); try ready(member.eventsLoad, deadline: member.deadline("events"))
                if case .event(let token) = destination, !member.events.contains(where: { $0.public_token == token }) { throw missing }
            case .registrations(let id):
                try available(member, "activity"); await member.loadActivity(); try ready(member.activityLoad, deadline: member.deadline("activity"))
                guard member.activity?.event_registrations?.contains(where: { $0.registration_id == id }) == true else { throw missing }
            case .spaces, .space:
                try available(member, "spaces"); await member.loadSpaces(); try ready(member.spacesLoad, deadline: member.deadline("spaces"))
                if case .space(let token) = destination, !member.spaces.contains(where: { $0.public_token == token }) { throw missing }
            case .payments, .payment:
                guard let payment else { throw unavailable("Payments aren't available in this build yet.") }
                if case .payment(let id) = destination { try await payment(id) } else { try await payment(nil) }
                guard router.isCurrent(value) else { return }; router.finish(value); return
            case .profile: break // The fresh /me response authorized this account-only destination.
            }
            guard router.isCurrent(value) else { return }
            switch destination {
            case .home: root(.home, navigation)
            case .inventory: root(.inventory, navigation)
            case .product(let id): navigation.inventorySelection = id; navigation.open(.product(id), tab: .inventory)
            case .activity, .bookings, .events: root(.activity, navigation)
            case .inbox: root(.inbox, navigation)
            case .profile: root(.profile, navigation)
            case .booking(let token): navigation.open(.booking(token), tab: .activity)
            case .event(let token): navigation.open(.event(token), tab: .activity)
            case .registrations(let id): navigation.open(.registration(id), tab: .activity)
            case .spaces: navigation.open(.spaces, tab: .activity)
            case .space(let token): navigation.open(.space(token), tab: .activity)
            case .payments, .payment: break
            }
            router.finish(value)
        } catch { router.destinationFailed(value, error: error) }
    }
    private static func root(_ tab: AppTab, _ navigation: MemberNavigation) { navigation.path(tab).wrappedValue = []; navigation.selected = tab }
    private static var missing: APIError { APIError(status: 404, code: "link_item_unavailable", detail: String(localized: "This item is no longer available. Open your inbox for the latest update.")) }
    private static func available(_ member: MemberState, _ role: String) throws {
        guard member.canLoad(role) else { throw unavailable(deadline: member.deadline(role)) }
    }
    private static func ready(_ load: MemberState.Load, deadline: Date?) throws {
        if case .ready = load { return }
        if case .failed(let message) = load { throw unavailable(message, deadline: deadline) }
        throw unavailable("This update is still loading. Try again in a moment.", deadline: deadline)
    }
    private static func unavailable(_ message: String? = nil, deadline: Date? = nil) -> APIError {
        APIError(status: deadline == nil ? 0 : 429, code: "link_unavailable", detail: message ?? String(localized: "Couldn't open this update. Try again."), retryAfter: deadline)
    }
}
