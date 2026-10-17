import Foundation

/// Staff API operations only. Native staff authority and visible actions are checked by the caller;
/// the server authorizes each generated operation. LiveStaffRepository binds the makerspace header.
extension SpaceWorksService {
    public func staffPendingRequests(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedAdminRequestList {
        try await client.api_v1_admin_makerspace_pending_requests_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffAcceptedRequests(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedAdminRequestList {
        try await client.api_v1_admin_makerspace_accepted_requests_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffActiveLoans(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedAdminRequestList {
        try await client.api_v1_admin_makerspace_active_loans_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffAcceptRequest(id: Int, body: Components.Schemas.AcceptRequest) async throws -> Components.Schemas.AdminRequest {
        try await client.api_v1_admin_requests_accept_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffRejectRequest(id: Int, body: Components.Schemas.RejectRequest) async throws -> Components.Schemas.AdminRequest {
        try await client.api_v1_admin_requests_reject_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffAssignBox(id: Int, body: Components.Schemas.AssignBox) async throws -> Components.Schemas.AdminRequest {
        try await client.api_v1_admin_requests_assign_box_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffIssueRequest(id: Int, body: Components.Schemas.IssueRequest) async throws -> Components.Schemas.AdminRequest {
        try await client.api_v1_admin_requests_issue_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffReturnRequest(id: Int, body: Components.Schemas.ReturnRequest) async throws -> Components.Schemas.AdminRequest {
        try await client.api_v1_admin_requests_return_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffResolveQR(body: Components.Schemas.QrResolve) async throws -> Components.Schemas.QrResolveResult {
        try await client.api_v1_admin_qr_resolve_create(.init(body: .json(body))).ok.body.json
    }
    public func staffDirectLoans(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedDirectLoanList {
        try await client.api_v1_admin_makerspace_direct_loans_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffDirectMembers(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedDirectLoanMemberList {
        try await client.api_v1_admin_makerspace_direct_loan_members_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffInventory(makerspaceID: Int, page: Int, search: String) async throws -> Components.Schemas.PaginatedInventoryProductAdminList {
        try await client.api_v1_admin_makerspace_inventory_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page, q: search.isEmpty ? nil : search))).ok.body.json
    }
    public func staffContainers(makerspaceID: Int, page: Int) async throws -> Components.Schemas.PaginatedBoxList {
        try await client.api_v1_admin_makerspace_containers_list(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffCreateDirectLoan(makerspaceID: Int, body: Components.Schemas.DirectLoanIssue) async throws -> Components.Schemas.DirectLoan {
        try await client.api_v1_admin_makerspace_direct_loans_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(body))).created.body.json
    }
    public func staffReturnDirectLoan(id: Int, body: Components.Schemas.DirectLoanReturn) async throws -> Components.Schemas.DirectLoan {
        try await client.api_v1_admin_direct_loans_return_create(.init(path: .init(id: id), body: .json(body))).ok.body.json
    }
    public func staffEvidence(makerspaceID: Int, body: Components.Schemas.EvidenceUrlRequest) async throws -> Components.Schemas.EvidenceUrlResponse {
        try await client.api_v1_admin_makerspaces_uploads_evidence_url_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(body))).created.body.json
    }
    public func staffKitPreview(makerspaceID: Int, body: Components.Schemas.KitPreviewInput) async throws -> Components.Schemas.KitPreview {
        try await client.api_v1_admin_makerspace_kit_checklist_preview_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(body))).ok.body.json
    }
    public func staffEvents(makerspaceID: Int, page: Int) async throws -> Components.Schemas.EventListWithDefaults {
        try await client.api_v1_admin_makerspaces_events_retrieve(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    /// Resolving identifies a registration. It never marks attendance automatically.
    public func staffResolveCheckIn(eventID: Int, body: Components.Schemas.EventCheckInResolveRequest) async throws -> Components.Schemas.EventCheckInResolveResponse {
        try await client.api_v1_admin_events_check_in_resolve_create(.init(path: .init(id: eventID), body: .json(body))).ok.body.json
    }
    public func staffMarkAttended(registrationID: Int, body: Components.Schemas.EventAttendanceMark) async throws -> Components.Schemas.EventRegistrationAdmin {
        try await client.api_v1_admin_event_registrations_mark_attended_create(.init(path: .init(id: registrationID), body: .json(body))).ok.body.json
    }
    public func staffSpaces(makerspaceID: Int, page: Int) async throws -> Components.Schemas.BookableSpaceListResponse {
        try await client.api_v1_admin_makerspaces_spaces_retrieve(.init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func staffBookings(spaceID: Int, page: Int) async throws -> Components.Schemas.BookingListResponse {
        try await client.api_v1_admin_spaces_bookings_retrieve(.init(path: .init(id: spaceID), query: .init(page: page))).ok.body.json
    }
    public func staffApproveBooking(id: Int) async throws -> Components.Schemas.BookingAdmin {
        try await client.api_v1_admin_bookings_approve_create(.init(path: .init(id: id))).ok.body.json
    }
    public func staffRejectBooking(id: Int) async throws -> Components.Schemas.BookingAdmin {
        try await client.api_v1_admin_bookings_reject_create(.init(path: .init(id: id))).ok.body.json
    }
}
