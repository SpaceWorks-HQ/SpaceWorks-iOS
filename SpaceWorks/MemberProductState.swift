import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable final class MemberProductState {
    let id: Int
    private(set) var product: Components.Schemas.PublicProduct?
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private(set) var busy = false
    private var active = true
    private let fetch: @Sendable () async throws -> Components.Schemas.PublicProduct
    init(id: Int, fetch: @escaping @Sendable () async throws -> Components.Schemas.PublicProduct) { self.id = id; self.fetch = fetch }
    func load(now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now else { return }
        product = nil; error = nil; busy = true; defer { busy = false }
        do { let value = try await fetch(); guard active else { return }; product = value; retryAfter = nil }
        catch { guard active else { return }; self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) }
    }
    func invalidate() { active = false; product = nil; error = nil; retryAfter = nil }
}
