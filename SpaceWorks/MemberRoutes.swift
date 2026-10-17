import SwiftUI
import SpaceWorksAPI

/// Destinations use IDs from confirmed lists. Never derive booking/registration IDs from titles.
struct MemberRouteView: View {
    let route: MemberRoute
    let member: MemberState
    let actions: any MemberActionsRepository
    let cart: RequestCartState
    let drafts: MemberActionDrafts
    let navigation: MemberNavigation
    let capabilities: MemberCapabilities
    let isDemo: Bool
    var payments: PaymentsState? = nil
    var staff: StaffState? = nil
    var account: AccountState? = nil
    #if DEBUG
    var onDemoDelete: (() -> Void)? = nil
    var onDemoFix: ((DemoDeletionState.Blocker) -> Void)? = nil
    #endif
    var profileSaved: () async -> Void = {}
    var body: some View {
        switch route {
        case .product(let id): InventoryDetail(repository: member.repository, id: id, cart: cart, drafts: drafts) { await member.loadActivity(); drafts.registrationCancelled() }
        case .bookings: MemberBookingsView(state: member)
        case .spaces: SpaceDiscoveryView(member: member, repository: actions, isDemo: isDemo) { await member.loadBookings() }
        case .space(let token):
            if let space = member.spaces.first(where: { $0.public_token == token }) {
                SpaceBookingView(repository: actions, space: space, isDemo: isDemo, drafts: drafts, viewActivity: showActivity) { await member.loadBookings() }
            } else { missing("Space unavailable", load: member.spacesLoad) { await member.loadSpaces() }.task { if member.spacesLoad == .idle { await member.loadSpaces() } } }
        case .event(let token):
            if let event = member.events.first(where: { $0.public_token == token }) {
                EventDetailView(event: event, repository: actions, isDemo: isDemo, drafts: drafts, viewActivity: showActivity) { await member.loadActivity() }
            } else { missing("Event unavailable", load: member.eventsLoad) { await member.loadEvents() }.task { if member.eventsLoad == .idle { await member.loadEvents() } } }
        case .booking(let token): BookingDestination(member: member, repository: actions, token: token, isDemo: isDemo)
        case .registration(let id): RegistrationDestination(member: member, repository: actions, id: id, isDemo: isDemo, drafts: drafts)
        case .account:
            if let account {
                #if DEBUG
                AccountView(state: account, privacyURL: Brand.privacyURL.flatMap(URL.init(string:)), supportURL: Brand.supportURL.flatMap(URL.init(string:)), onDemoDelete: onDemoDelete, onDemoFix: onDemoFix)
                #else
                AccountView(state: account, privacyURL: Brand.privacyURL.flatMap(URL.init(string:)), supportURL: Brand.supportURL.flatMap(URL.init(string:)))
                #endif
            } else { disabledFeature("Sign in again to manage this account.") }
        case .staff:
            if let staff { StaffView(state: staff) }
            else { disabledFeature("Staff tools require an authorized native staff session.") }
        case .payments:
            if let payments { PaymentsView(state: payments) }
            else { disabledFeature("Payments are unavailable. Try again later.") }
        case .payment(let id):
            if let payments { PaymentDetailView(state: payments, paymentID: id) }
            else { disabledFeature("Payments are unavailable. Try again later.") }
        case .contact:
            if capabilities.selfService { ProfileEditorView(repository: actions, isDemo: isDemo, drafts: drafts, saved: profileSaved) }
            else { disabledFeature("Account self-service is disabled for this makerspace.") }
        case .preferences:
            if capabilities.preferences { CommunicationPreferencesView(repository: actions, isDemo: isDemo, drafts: drafts, digestsEnabled: capabilities.digests) }
            else { disabledFeature("Communication preferences aren't available in this makerspace.") }
        }
    }
    private func disabledFeature(_ message: String) -> some View {
        ScrollView { SWCard { Text(message).foregroundStyle(Color.swMuted) }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity) }.background(Color.swBg)
    }
    private func showActivity() { navigation.path(.activity).wrappedValue = []; navigation.selected = .activity }
    private func missing(_ title: String, load: MemberState.Load, retry: @escaping () async -> Void) -> some View {
        ScrollView {
            SWCard {
                LoadFeedback(load: load, retry: retry)
                if load == .ready { Text(title).brandFont(.headline); Text("Refresh the list and choose an available item.").foregroundStyle(Color.swMuted) }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}

private struct BookingDestination: View {
    let member: MemberState
    let repository: any MemberActionsRepository
    let token: String
    let isDemo: Bool
    @State private var initial: Components.Schemas.MemberBooking?
    var body: some View {
        Group {
            if let initial { MemberBookingDetailView(booking: initial, repository: repository, isDemo: isDemo) { await member.loadBookings() } }
            else { ProgressView("Loading booking…") }
        }.task { initial = member.bookings.first(where: { $0.public_token == token }) }
    }
}

private struct RegistrationDestination: View {
    let member: MemberState
    let repository: any MemberActionsRepository
    let id: Int
    let isDemo: Bool
    let drafts: MemberActionDrafts
    @State private var initial: Components.Schemas.MemberEventRegistrationActivity?
    var body: some View {
        Group {
            if let initial { MemberRegistrationView(registration: initial, repository: repository, isDemo: isDemo, drafts: drafts) { await member.loadActivity() } }
            else { ProgressView("Loading registration…") }
        }.task { initial = member.activity?.event_registrations?.first(where: { $0.registration_id == id }) }
    }
}
