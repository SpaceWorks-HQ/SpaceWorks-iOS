import Foundation
import SpaceWorksAPI

/// Local navigation selection; never serialized as an API request.
enum StaffQueue: String, CaseIterable, Sendable { case pending, accepted, active }

protocol StaffRepository: Sendable {
    var isDemo: Bool { get }
    func requests(queue: StaffQueue, page: Int) async throws -> Components.Schemas.PaginatedAdminRequestList
    func accept(id: Int, body: Components.Schemas.AcceptRequest) async throws -> Components.Schemas.AdminRequest
    func reject(id: Int, body: Components.Schemas.RejectRequest) async throws -> Components.Schemas.AdminRequest
    func assignBox(id: Int, body: Components.Schemas.AssignBox) async throws -> Components.Schemas.AdminRequest
    func issue(id: Int, body: Components.Schemas.IssueRequest) async throws -> Components.Schemas.AdminRequest
    func returnRequest(id: Int, body: Components.Schemas.ReturnRequest) async throws -> Components.Schemas.AdminRequest
    func resolveQR(body: Components.Schemas.QrResolve) async throws -> Components.Schemas.QrResolveResult
    func directLoans(page: Int) async throws -> Components.Schemas.PaginatedDirectLoanList
    func directMembers(page: Int) async throws -> Components.Schemas.PaginatedDirectLoanMemberList
    func inventory(page: Int, search: String) async throws -> Components.Schemas.PaginatedInventoryProductAdminList
    func containers(page: Int) async throws -> Components.Schemas.PaginatedBoxList
    func createDirect(body: Components.Schemas.DirectLoanIssue) async throws -> Components.Schemas.DirectLoan
    func returnDirect(id: Int, body: Components.Schemas.DirectLoanReturn) async throws -> Components.Schemas.DirectLoan
    func evidence(body: Components.Schemas.EvidenceUrlRequest) async throws -> Components.Schemas.EvidenceUrlResponse
    func kitPreview(body: Components.Schemas.KitPreviewInput) async throws -> Components.Schemas.KitPreview
    func events(page: Int) async throws -> Components.Schemas.EventListWithDefaults
    func resolveCheckIn(eventID: Int, body: Components.Schemas.EventCheckInResolveRequest) async throws -> Components.Schemas.EventCheckInResolveResponse
    func markAttended(registrationID: Int, body: Components.Schemas.EventAttendanceMark) async throws -> Components.Schemas.EventRegistrationAdmin
    func spaces(page: Int) async throws -> Components.Schemas.BookableSpaceListResponse
    func bookings(spaceID: Int, page: Int) async throws -> Components.Schemas.BookingListResponse
    func approveBooking(id: Int) async throws -> Components.Schemas.BookingAdmin
    func rejectBooking(id: Int) async throws -> Components.Schemas.BookingAdmin
}
extension StaffRepository { var isDemo: Bool { false } }

/// Immutable scope for every read and mutation, including ID-only API routes.
/// Construct only after native_staff authority and the selected membership's actions are verified.
struct LiveStaffRepository: StaffRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot?
    let makerspaceID: Int
    let origin: ServerOrigin
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }
    var onForbidden: @Sendable () async -> Void = {}

    private func checked<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard let expectedCredentials, await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        guard makerspaceID > 0 else { throw CancellationError() }
        do { return try await service.withMakerspace(makerspaceID, expectedCredentials: expectedCredentials, operation: work) }
        catch {
            if Task.isCancelled || APIError.isCancellation(error) { throw error }
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            let empty = await service.refresh.current() == nil
            if APIError.status(error) == 401 || empty { await onUnauthorized(APIError.display(error)) }
            else if APIError.status(error) == 403 { await onForbidden() }
            throw error
        }
    }
    /// Links are checked, never fetched. The state parses the actual page and calls this repository again.
    private func validate(_ next: String?, path: String, after page: Int) throws {
        guard let next else { return }
        guard next.utf8.count <= 8192, !next.contains("\\"),
              !next.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let base = URL(string: path, relativeTo: origin.url)?.absoluteURL,
              let absolute = URL(string: next, relativeTo: base)?.absoluteURL,
              let validated = try origin.nextPage(absolute.absoluteString),
              let parts = URLComponents(url: validated, resolvingAgainstBaseURL: true),
              parts.percentEncodedPath == path, let items = parts.queryItems, items.count == 1,
              items[0].name == "page", let raw = items[0].value, !raw.isEmpty,
              raw.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(raw), number > page else {
            throw APIError(status: 0, code: "invalid_next_page", detail: "The next staff page is unavailable. Refresh and try again.")
        }
    }
    func requests(queue: StaffQueue, page: Int) async throws -> Components.Schemas.PaginatedAdminRequestList {
        let result: Components.Schemas.PaginatedAdminRequestList
        let suffix: String
        switch queue {
        case .pending:
            result = try await checked { try await service.staffPendingRequests(makerspaceID: makerspaceID, page: page) }; suffix = "pending-requests"
        case .accepted:
            result = try await checked { try await service.staffAcceptedRequests(makerspaceID: makerspaceID, page: page) }; suffix = "accepted-requests"
        case .active:
            result = try await checked { try await service.staffActiveLoans(makerspaceID: makerspaceID, page: page) }; suffix = "active-loans"
        }
        try validate(result.next, path: "/api/v1/admin/makerspace/\(makerspaceID)/\(suffix)", after: page)
        return result
    }
    func accept(id: Int, body: Components.Schemas.AcceptRequest) async throws -> Components.Schemas.AdminRequest { try await checked { try await service.staffAcceptRequest(id: id, body: body) } }
    func reject(id: Int, body: Components.Schemas.RejectRequest) async throws -> Components.Schemas.AdminRequest { try await checked { try await service.staffRejectRequest(id: id, body: body) } }
    func assignBox(id: Int, body: Components.Schemas.AssignBox) async throws -> Components.Schemas.AdminRequest { try await checked { try await service.staffAssignBox(id: id, body: body) } }
    func issue(id: Int, body: Components.Schemas.IssueRequest) async throws -> Components.Schemas.AdminRequest { try await checked { try await service.staffIssueRequest(id: id, body: body) } }
    func returnRequest(id: Int, body: Components.Schemas.ReturnRequest) async throws -> Components.Schemas.AdminRequest { try await checked { try await service.staffReturnRequest(id: id, body: body) } }
    func resolveQR(body: Components.Schemas.QrResolve) async throws -> Components.Schemas.QrResolveResult { try await checked { try await service.staffResolveQR(body: body) } }
    func directLoans(page: Int) async throws -> Components.Schemas.PaginatedDirectLoanList {
        let result = try await checked { try await service.staffDirectLoans(makerspaceID: makerspaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/makerspace/\(makerspaceID)/direct-loans", after: page); return result
    }
    func directMembers(page: Int) async throws -> Components.Schemas.PaginatedDirectLoanMemberList {
        let result = try await checked { try await service.staffDirectMembers(makerspaceID: makerspaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/makerspace/\(makerspaceID)/direct-loan-members", after: page); return result
    }
    func inventory(page: Int, search: String) async throws -> Components.Schemas.PaginatedInventoryProductAdminList {
        let result = try await checked { try await service.staffInventory(makerspaceID: makerspaceID, page: page, search: search) }
        // Inventory next links may retain the generated search query; no URL is ever used as a request.
        try validateInventory(result.next, page: page, search: search); return result
    }
    private func validateInventory(_ next: String?, page: Int, search: String) throws {
        guard let next else { return }
        guard var parts = URLComponents(string: next) else {
            throw APIError(status: 0, code: "invalid_next_page", detail: "The next staff page is unavailable. Refresh and try again.")
        }
        let query = parts.queryItems ?? []
        guard query.filter({ $0.name == "q" }).count <= 1,
              query.allSatisfy({ $0.name == "page" || ($0.name == "q" && $0.value == search) }) else {
            throw APIError(status: 0, code: "invalid_next_page", detail: "The next staff page is unavailable. Refresh and try again.")
        }
        parts.queryItems = query.filter { $0.name == "page" }
        try validate(parts.string, path: "/api/v1/admin/makerspace/\(makerspaceID)/inventory", after: page)
    }
    func containers(page: Int) async throws -> Components.Schemas.PaginatedBoxList {
        let result = try await checked { try await service.staffContainers(makerspaceID: makerspaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/makerspace/\(makerspaceID)/containers", after: page); return result
    }
    func createDirect(body: Components.Schemas.DirectLoanIssue) async throws -> Components.Schemas.DirectLoan { try await checked { try await service.staffCreateDirectLoan(makerspaceID: makerspaceID, body: body) } }
    func returnDirect(id: Int, body: Components.Schemas.DirectLoanReturn) async throws -> Components.Schemas.DirectLoan { try await checked { try await service.staffReturnDirectLoan(id: id, body: body) } }
    func evidence(body: Components.Schemas.EvidenceUrlRequest) async throws -> Components.Schemas.EvidenceUrlResponse { try await checked { try await service.staffEvidence(makerspaceID: makerspaceID, body: body) } }
    func kitPreview(body: Components.Schemas.KitPreviewInput) async throws -> Components.Schemas.KitPreview { try await checked { try await service.staffKitPreview(makerspaceID: makerspaceID, body: body) } }
    func events(page: Int) async throws -> Components.Schemas.EventListWithDefaults {
        let result = try await checked { try await service.staffEvents(makerspaceID: makerspaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/makerspaces/\(makerspaceID)/events/", after: page); return result
    }
    func resolveCheckIn(eventID: Int, body: Components.Schemas.EventCheckInResolveRequest) async throws -> Components.Schemas.EventCheckInResolveResponse { try await checked { try await service.staffResolveCheckIn(eventID: eventID, body: body) } }
    func markAttended(registrationID: Int, body: Components.Schemas.EventAttendanceMark) async throws -> Components.Schemas.EventRegistrationAdmin { try await checked { try await service.staffMarkAttended(registrationID: registrationID, body: body) } }
    func spaces(page: Int) async throws -> Components.Schemas.BookableSpaceListResponse {
        let result = try await checked { try await service.staffSpaces(makerspaceID: makerspaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/makerspaces/\(makerspaceID)/spaces/", after: page); return result
    }
    func bookings(spaceID: Int, page: Int) async throws -> Components.Schemas.BookingListResponse {
        let result = try await checked { try await service.staffBookings(spaceID: spaceID, page: page) }
        try validate(result.next, path: "/api/v1/admin/spaces/\(spaceID)/bookings/", after: page); return result
    }
    func approveBooking(id: Int) async throws -> Components.Schemas.BookingAdmin { try await checked { try await service.staffApproveBooking(id: id) } }
    func rejectBooking(id: Int) async throws -> Components.Schemas.BookingAdmin { try await checked { try await service.staffRejectBooking(id: id) } }
}
