import Foundation
import Observation
import UIKit
import SpaceWorksAPI

@MainActor @Observable final class MemberTicketState {
    let registration: Components.Schemas.MemberEventRegistrationActivity
    let repository: any MemberActionsRepository
    private(set) var image: UIImage?
    private(set) var error: String?
    private(set) var busy = false
    private(set) var cancelled = false
    private(set) var retryAfter: Date?
    private var active = true
    private var generation = 0
    private var cancelling = false
    init(registration: Components.Schemas.MemberEventRegistrationActivity, repository: any MemberActionsRepository) { self.registration = registration; self.repository = repository }
    func load(now: Date = Date()) async {
        guard active, !cancelled, registration.status == "registered", !cancelling, (retryAfter ?? .distantPast) <= now else { return }
        image = nil; error = nil; generation += 1; let expected = generation
        busy = true; defer { if expected == generation { busy = false } }
        do {
            let data = try await repository.eventQR(registration: registration.registration_id)
            guard active, !cancelled, expected == generation else { return }
            guard let rendered = NativeQRSVG.image(data) else { error = "This ticket image could not be opened. Try again or ask the event desk for help."; return }
            image = rendered; retryAfter = nil
        } catch { if active, expected == generation { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func cancel(now: Date = Date()) async {
        guard active, !busy, !cancelled, registration.can_cancel, (retryAfter ?? .distantPast) <= now else { return }
        generation += 1; cancelling = true; busy = true; image = nil; error = nil; defer { busy = false; cancelling = false }
        do { _ = try await repository.cancelEvent(registration: registration.registration_id); guard active else { return }; cancelled = true; retryAfter = nil }
        catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
    func invalidate() { active = false; generation += 1; image = nil; error = nil; retryAfter = nil }
}
