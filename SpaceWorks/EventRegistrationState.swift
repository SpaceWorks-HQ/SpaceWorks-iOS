import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class EventRegistrationState {
    let repository: any MemberActionsRepository
    let event: Components.Schemas.PublicEvent
    let form: MemberCustomForm
    var phone = ""
    var email = ""
    var invite = ""
    var promo = ""
    var ticket: Int?
    private(set) var result: Components.Schemas.PublicEventRegistrationResponse?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private var active = true
    init(repository: any MemberActionsRepository, event: Components.Schemas.PublicEvent) {
        self.repository = repository; self.event = event
        form = MemberCustomForm(data: event.custom_form.flatMap { try? JSONEncoder().encode($0) })
    }
    func submit(now: Date = Date()) async {
        guard active, !busy, result == nil, (retryAfter ?? .distantPast) <= now else { return }
        guard event.registration_open else { error = "Registration is closed."; return }
        guard !event.ticket_selection_required || ticket != nil else { error = "Choose a ticket type."; return }
        if let ticket, !event.ticket_types.contains(where: { $0.id == ticket }) { error = "Choose an available ticket type."; return }
        guard phone.count <= 64, invite.count <= 128, promo.count <= 128 else { error = "Check your contact details and codes, then try again."; return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.isEmpty || (normalizedEmail.contains("@") && !normalizedEmail.contains(where: { $0.isWhitespace })) else { error = "Enter a valid email address."; return }
        guard event.registration_audience.value1 != .invite || !invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter your invitation code."; return }
        guard let answers = form.validatedAnswers() else { error = form.unavailable ? "This form isn't supported in the app yet." : "Check the highlighted questions."; return }
        var body: [String: Any] = ["custom_answers": answers]
        for (key, value) in [("phone", phone), ("email", email), ("invite_code", invite), ("promo_code", promo)] where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ticket { body["ticket_type_id"] = ticket }
        busy = true; error = nil; defer { busy = false }
        do {
            let input = try JSONDecoder().decode(Components.Schemas.PublicEventRegistrationInput.self, from: JSONSerialization.data(withJSONObject: body))
            let response = try await repository.register(event: event.public_token, input: input)
            guard active else { return }; result = response
        } catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func resetReceipt() { if active && !busy { result = nil; error = nil } }
    func invalidate() { active = false; result = nil; phone = ""; email = ""; invite = ""; promo = ""; form.text = [:]; form.multiple = [:]; error = nil }
}
