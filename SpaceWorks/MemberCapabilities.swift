import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable final class MemberCapabilities {
    private(set) var bootstrap: Components.Schemas.TenantBootstrap?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private var active = true
    let repository: any MemberActionsRepository
    let makerspaceID: Int
    init(repository: any MemberActionsRepository, makerspaceID: Int) { self.repository = repository; self.makerspaceID = makerspaceID }
    var selfService: Bool { bootstrap?.modules.contains("membership") == true && bootstrap?.modules.contains("member_accounts") == true && bootstrap?.features.contains("membership.self_service") == true }
    var preferences: Bool { bootstrap?.modules.contains("notifications") == true && bootstrap?.features.contains("notifications.member_preferences") == true }
    var digests: Bool { preferences && bootstrap?.features.contains("notifications.digests") == true }
    func load(now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let value = try await repository.bootstrap(); guard active else { return }
            guard value.makerspace.id == makerspaceID else { throw APIError(status: 403, code: "wrong_makerspace", detail: "This configuration belongs to another makerspace.") }
            bootstrap = value; retryAfter = nil
        } catch { guard active else { return }; bootstrap = nil; self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) }
    }
    func invalidate() { active = false; bootstrap = nil; error = nil }
}
