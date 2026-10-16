import Foundation
import SpaceWorksAPI

/// Drafts survive phone/tablet layout reconstruction, and end with their account/makerspace.
@MainActor final class MemberActionDrafts {
    let repository: any MemberActionsRepository
    private var tickets: [Int: MemberTicketState] = [:]
    private var products: [Int: MemberProductState] = [:]
    private var bookings: [String: BookingState] = [:]
    private var forms: [String: MemberCustomForm] = [:]
    private var events: [String: EventRegistrationState] = [:]
    let profile: ProfileEditorState
    let preferences: CommunicationPreferencesState
    init(repository: any MemberActionsRepository) { self.repository = repository; profile = ProfileEditorState(repository: repository); preferences = CommunicationPreferencesState(repository: repository) }
    func ticket(_ registration: Components.Schemas.MemberEventRegistrationActivity) -> MemberTicketState {
        if let state = tickets[registration.registration_id], state.registration == registration { return state }
        tickets[registration.registration_id]?.invalidate()
        let state = MemberTicketState(registration: registration, repository: repository); tickets[registration.registration_id] = state; return state
    }
    func registrationCancelled() { events.values.forEach { $0.resetReceipt() } }
    func product(_ id: Int, repository: any MemberRepository) -> MemberProductState {
        if let state = products[id] { return state }
        let state = MemberProductState(id: id) { try await repository.product(id) }; products[id] = state; return state
    }
    func booking(_ space: Components.Schemas.PublicBookableSpace) -> BookingState {
        if let state = bookings[space.public_token] { return state }
        let state = BookingState(repository: repository, space: space); bookings[space.public_token] = state; return state
    }
    func form(_ space: Components.Schemas.PublicBookableSpace) -> MemberCustomForm {
        if let form = forms[space.public_token] { return form }
        let form = MemberCustomForm(data: space.custom_form.flatMap { try? JSONEncoder().encode($0) }); forms[space.public_token] = form; return form
    }
    func event(_ event: Components.Schemas.PublicEvent) -> EventRegistrationState {
        if let state = events[event.public_token] { return state }
        let state = EventRegistrationState(repository: repository, event: event); events[event.public_token] = state; return state
    }
    func invalidate() {
        tickets.values.forEach { $0.invalidate() }; tickets = [:]
        products.values.forEach { $0.invalidate() }; products = [:]
        bookings.values.forEach { $0.invalidate() }; events.values.forEach { $0.invalidate() }; profile.invalidate(); preferences.invalidate()
        bookings = [:]; forms = [:]; events = [:]
    }
}
