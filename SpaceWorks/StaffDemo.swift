#if DEBUG
import Foundation
import SpaceWorksAPI

enum DemoStaffScenario: String, CaseIterable, Sendable {
    case populated = "Populated", empty = "Empty", offline = "Error", uploadRefused = "Photo refused"
    case issueConflict = "Issue conflict", waitlisted = "Waitlisted check-in", attendanceConflict = "Check-in changed"
    case bookingConflict = "Booking changed"
}

/// Entirely local sample records. No live gateway, payment SDK, scanner mutation or upload is used.
actor DemoStaffRepository: StaffRepository {
    nonisolated let isDemo = true
    let scenario: DemoStaffScenario
    let makerspaceID: Int
    private var statuses = [601: "pending", 602: "accepted", 603: "issued"]
    private var assignments = Set<Int>()
    private var directCreated = false
    private var directReturned = false
    private var attended = false
    private var bookingStatus = "pending"
    private var evidenceCounter = 1300
    private let beforeEvents: @Sendable () async -> Void
    private let beforeEvidence: @Sendable () async -> Void
    init(scenario: DemoStaffScenario = .populated, makerspaceID: Int = 7, beforeEvents: @escaping @Sendable () async -> Void = {},
         beforeEvidence: @escaping @Sendable () async -> Void = {}) {
        self.scenario = scenario; self.makerspaceID = makerspaceID; self.beforeEvents = beforeEvents; self.beforeEvidence = beforeEvidence
    }
    private func checked() throws { if scenario == .offline { throw URLError(.notConnectedToInternet) } }
    private func decode<T: Decodable>(_ json: String, changes: [String: Any] = [:]) throws -> T {
        try checked()
        var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        if object["makerspace_id"] != nil { object["makerspace_id"] = makerspaceID }
        object.merge(changes) { _, new in new }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func page<T: Decodable, Row: Encodable>(_ rows: [Row], page: Int, extra: [String: Any] = [:]) throws -> T {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let values = try JSONSerialization.jsonObject(with: encoder.encode(rows))
        var object: [String: Any] = ["count": scenario == .empty ? 0 : rows.count, "next": NSNull(), "previous": NSNull(), "results": scenario == .empty || page > 1 ? [] : values]
        object.merge(extra) { _, new in new }
        return try decode(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func requests(queue: StaffQueue, page: Int) throws -> Components.Schemas.PaginatedAdminRequestList {
        let target = queue == .pending ? "pending" : queue == .accepted ? "accepted" : "issued"
        let rows: [Components.Schemas.AdminRequest] = try statuses.keys.sorted().filter { statuses[$0] == target }.map { try request($0) }
        return try self.page(rows, page: page)
    }
    private func request(_ id: Int) throws -> Components.Schemas.AdminRequest {
        guard let status = statuses[id] else { throw APIError(status: 404, code: "not_found", detail: "Sample request unavailable.") }
        var object = try JSONSerialization.jsonObject(with: Data(DebugStaffFixtures.request.utf8)) as! [String: Any]
        var items = object["items"] as! [[String: Any]]
        items[0]["issued_quantity"] = status == "issued" || status == "closed" ? 2 : 0
        items[0]["returned_quantity"] = status == "closed" ? 2 : 0
        object["items"] = items
        return try decode(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self), changes: ["id": id, "status": status])
    }
    func accept(id: Int, body: Components.Schemas.AcceptRequest) throws -> Components.Schemas.AdminRequest {
        try checked(); statuses[id] = "accepted"; return try request(id)
    }
    func reject(id: Int, body: Components.Schemas.RejectRequest) throws -> Components.Schemas.AdminRequest {
        try checked(); statuses[id] = "rejected"; return try request(id)
    }
    func assignBox(id: Int, body: Components.Schemas.AssignBox) throws -> Components.Schemas.AdminRequest {
        try checked(); guard statuses[id] == "accepted", body.box_code == "DEMO-BOX" else { throw APIError(status: 409, code: "changed", detail: "Sample container or request changed.") }
        assignments.insert(id); return try request(id)
    }
    func issue(id: Int, body: Components.Schemas.IssueRequest) throws -> Components.Schemas.AdminRequest {
        try checked()
        if scenario == .issueConflict { throw APIError(status: 409, code: "issue_conflict", detail: "The request changed before issue completed.") }
        guard statuses[id] == "accepted", assignments.contains(id) else { throw APIError(status: 409, code: "changed", detail: "Refresh the sample request.") }
        statuses[id] = "issued"; return try request(id)
    }
    func returnRequest(id: Int, body: Components.Schemas.ReturnRequest) throws -> Components.Schemas.AdminRequest {
        try checked(); statuses[id] = "closed"; return try request(id)
    }
    func resolveQR(body: Components.Schemas.QrResolve) throws -> Components.Schemas.QrResolveResult {
        guard ["DEMO-BOX", "DEMO-TOOL"].contains(body.payload) else { throw APIError(status: 404, code: "not_found", detail: "Use DEMO-BOX or DEMO-TOOL in this sample.") }
        var object = try JSONSerialization.jsonObject(with: Data(DebugStaffFixtures.qr.utf8)) as! [String: Any]
        if body.payload == "DEMO-TOOL" {
            var qr = object["qr"] as! [String: Any]; qr["id"] = 1202; qr["payload"] = body.payload; qr["target_type"] = "product"; qr["target_id"] = 901; object["qr"] = qr
            object["target"] = ["type": "product", "id": 901, "label": "Sample precision toolkit", "product_id": 901]
            object["allowed_actions"] = ["view", "direct_handout"]
        }
        return try decode(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func directLoans(page: Int) throws -> Components.Schemas.PaginatedDirectLoanList {
        let row: Components.Schemas.DirectLoan = try decode(DebugStaffFixtures.loan, changes: ["status": directReturned ? "returned" : "active"])
        return try self.page([row], page: page)
    }
    func directMembers(page: Int) throws -> Components.Schemas.PaginatedDirectLoanMemberList {
        let initial: Components.Schemas.PaginatedDirectLoanMemberList = try decode(DebugStaffFixtures.members)
        return try self.page(initial.results, page: page)
    }
    func inventory(page: Int, search: String) throws -> Components.Schemas.PaginatedInventoryProductAdminList {
        let initial: Components.Schemas.PaginatedInventoryProductAdminList = try decode(DebugStaffFixtures.inventory)
        return try self.page(initial.results.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, page: page)
    }
    func containers(page: Int) throws -> Components.Schemas.PaginatedBoxList { try decode(DebugStaffFixtures.containers) }
    func createDirect(body: Components.Schemas.DirectLoanIssue) throws -> Components.Schemas.DirectLoan {
        try checked(); directCreated = true; return try decode(DebugStaffFixtures.loan)
    }
    func returnDirect(id: Int, body: Components.Schemas.DirectLoanReturn) throws -> Components.Schemas.DirectLoan {
        try checked(); directReturned = true; return try decode(DebugStaffFixtures.loan, changes: ["status": "returned"])
    }
    func evidence(body: Components.Schemas.EvidenceUrlRequest) async throws -> Components.Schemas.EvidenceUrlResponse {
        await beforeEvidence()
        try checked()
        if scenario == .uploadRefused { throw APIError(status: 403, code: "upload_refused", detail: "The sample evidence upload was refused.") }
        evidenceCounter += 1
        return try decode(#"{"evidence_id":0,"upload_url":"https://storage.example.invalid/demo-only","object_key":"demo-only","fields":{}}"#, changes: ["evidence_id": evidenceCounter])
    }
    func kitPreview(body: Components.Schemas.KitPreviewInput) throws -> Components.Schemas.KitPreview { try decode(DebugStaffFixtures.kits) }
    func events(page: Int) async throws -> Components.Schemas.EventListWithDefaults {
        await beforeEvents()
        let row: Components.Schemas.EventAdmin = try decode(DebugStaffFixtures.event)
        return try self.page([row], page: page, extra: ["default_registration_audience": "members"])
    }
    func resolveCheckIn(eventID: Int, body: Components.Schemas.EventCheckInResolveRequest) throws -> Components.Schemas.EventCheckInResolveResponse {
        guard eventID == 801, body.checkin_token == "DEMO-EVENT" else { throw APIError(status: 404, code: "not_found", detail: "That is not a check-in code for this event.") }
        let status = attended ? "attended" : scenario == .waitlisted ? "waitlisted" : "registered"
        return try decode(DebugStaffFixtures.checkin, changes: ["status": status, "confirmable": status == "registered"])
    }
    func markAttended(registrationID: Int, body: Components.Schemas.EventAttendanceMark) throws -> Components.Schemas.EventRegistrationAdmin {
        try checked()
        if scenario == .attendanceConflict { throw APIError(status: 409, code: "changed", detail: "This registration changed.") }
        guard registrationID == 1101, !attended, scenario != .waitlisted else { throw APIError(status: 409, code: "changed", detail: "This registration changed.") }
        attended = true; return try decode(DebugStaffFixtures.registration, changes: ["status": "attended"])
    }
    func spaces(page: Int) throws -> Components.Schemas.BookableSpaceListResponse {
        let row: Components.Schemas.BookableSpaceAdmin = try decode(DebugStaffFixtures.space)
        return try self.page([row], page: page)
    }
    func bookings(spaceID: Int, page: Int) throws -> Components.Schemas.BookingListResponse {
        let row: Components.Schemas.BookingAdmin = try decode(DebugStaffFixtures.booking, changes: ["status": bookingStatus])
        return try self.page(spaceID == row.space_id ? [row] : [], page: page)
    }
    func approveBooking(id: Int) throws -> Components.Schemas.BookingAdmin {
        try checked(); bookingStatus = "confirmed"
        if scenario == .bookingConflict { throw APIError(status: 409, code: "changed", detail: "This booking changed. Refresh its status.") }
        return try decode(DebugStaffFixtures.booking, changes: ["status": bookingStatus])
    }
    func rejectBooking(id: Int) throws -> Components.Schemas.BookingAdmin { try checked(); bookingStatus = "rejected"; return try decode(DebugStaffFixtures.booking, changes: ["status": bookingStatus]) }
}
#endif
