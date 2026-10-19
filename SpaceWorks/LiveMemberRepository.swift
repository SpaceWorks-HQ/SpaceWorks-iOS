import Foundation
import SpaceWorksAPI

struct LiveMemberRepository: MemberRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot?
    let origin: ServerOrigin
    let id: Int
    let slug: String
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }
    var onForbidden: @Sendable () async -> Void = {}
    private func checked<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard let expectedCredentials, await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        do { return try await service.withMakerspace(id, expectedCredentials: expectedCredentials, operation: work) }
        catch {
            if Task.isCancelled || APIError.isCancellation(error) { throw error }
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            let empty = await service.refresh.current() == nil
            if APIError.status(error) == 401 || empty { await onUnauthorized(APIError.display(error)) }
            else if APIError.status(error) == 403 { await onForbidden() }
            throw error
        }
    }
    func inventory(page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList {
        let result = try await checked { try await service.memberInventory(slug: slug, page: page, search: search, category: category) }
        _ = try origin.nextPage(result.next)
        return result
    }
    func product(_ id: Int) async throws -> Components.Schemas.PublicProduct { try await checked { try await service.memberProduct(slug: slug, id: id) } }
    func categories() async throws -> [Components.Schemas.PublicCategory] { try await checked { try await service.memberCategories(slug: slug) } }
    func activity() async throws -> Components.Schemas.MemberActivity { try await checked { try await service.memberActivity(id: id) } }
    func bookings(page: Int) async throws -> Components.Schemas.MemberBookingList {
        let result = try await checked { try await service.memberBookings(slug: slug, page: page) }
        _ = try origin.nextPage(result.next)
        return result
    }
    func events() async throws -> [Components.Schemas.PublicEvent] { try await checked { try await service.memberEvents(slug: slug) } }
    func spaces() async throws -> [Components.Schemas.PublicBookableSpace] { try await checked { try await service.memberSpaces(slug: slug) } }
    func card() async throws -> Components.Schemas.OwnMemberCard { try await checked { try await service.memberCard(id: id) } }
    func inbox(page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage {
        let result = try await checked { try await service.memberInbox(id: id, page: page, unread: unread) }
        _ = try origin.nextPage(result.next)
        return result
    }
    func markRead(_ message: Int) async throws { try await checked { try await service.memberMarkRead(id: id, message: message) } }
    func markAllRead() async throws { try await checked { try await service.memberMarkAllRead(id: id) } }
    func unreadCount() async throws -> Int { try await checked { try await service.memberUnreadCount(id: id).count } }
}
