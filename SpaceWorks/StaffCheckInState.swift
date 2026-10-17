import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class StaffCheckInState {
    let parent: StaffState
    private let eventID: Int
    private let eventMakerspaceID: Int
    private(set) var eventTitle: String
    private(set) var person: Components.Schemas.EventCheckInResolveResponse?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var confirmation: String?
    private var generation = 0
    private var active = true
    init(parent: StaffState, event: Components.Schemas.EventAdmin) {
        self.parent = parent; self.eventID = event.id; self.eventMakerspaceID = event.makerspace_id; self.eventTitle = event.title
        parent.registerChild { [weak self] in self?.invalidate() }
    }
    var canConfirm: Bool { active && parent.canRequest && parent.can("manage_events") && !busy && person?.status == "registered" && person?.confirmable == true }
    func invalidate() { active = false; generation += 1; person = nil; confirmation = nil; error = nil; busy = false; eventTitle = "" }
    func resolve(_ token: String) async {
        guard active, parent.canRequest, parent.can("manage_events"), !busy, eventMakerspaceID == parent.makerspaceID else { return }
        generation += 1; let current = generation; person = nil; confirmation = nil; error = nil
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2048, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { error = "Enter a valid check-in code."; return }
        busy = true
        do {
            let resolved = try await parent.repository.resolveCheckIn(eventID: eventID, body: .init(checkin_token: value))
            guard active, current == generation else { return }; person = resolved; busy = false
        } catch {
            guard active, current == generation else { return }; busy = false; parent.refuse(error)
            self.error = APIError.status(error) == 404 ? "That is not a check-in code for this event." : APIError.display(error)
        }
    }
    /// Called only by the separate visible confirmation button, never by the camera callback.
    func confirm() async {
        guard canConfirm, let person else { return }; busy = true; error = nil
        let current = generation
        do {
            _ = try await parent.repository.markAttended(registrationID: person.registration_id, body: .init(source: .init(value1: .qr)))
            guard active, current == generation else { return }
            confirmation = "Attendance recorded for \(person.name)."; self.person = nil; busy = false
        } catch {
            guard active, current == generation else { return }; self.person = nil; busy = false; parent.refuse(error)
            self.error = APIError.status(error) == 409 ? "This registration changed. Scan the code again to check its latest status." : APIError.display(error)
        }
    }
}
