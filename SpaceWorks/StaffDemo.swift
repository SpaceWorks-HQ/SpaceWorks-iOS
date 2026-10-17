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
    private var requestRecords: [Int: Components.Schemas.AdminRequest] = [:]
    private var loanRecords: [Int: Components.Schemas.DirectLoan] = [:]
    private var nextLoanID = 702
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
    private func changed() -> APIError {
        APIError(status: 409, code: "changed", detail: String(localized: "This changed. Refresh and try again."))
    }
    private func request(_ id: Int) throws -> Components.Schemas.AdminRequest {
        try checked()
        if let saved = requestRecords[id] { return saved }
        guard let status = statuses[id] else { throw changed() }
        var row: Components.Schemas.AdminRequest = try decode(DebugStaffFixtures.request, changes: ["id": id, "status": status])
        row.items = row.items.map { initial in
            var item = initial
            item.accepted_quantity = status == "pending" ? 0 : item.requested_quantity
            item.issued_quantity = status == "issued" ? item.accepted_quantity : 0
            item.returned_quantity = 0; item.damaged_quantity = 0; item.missing_quantity = 0
            return item
        }
        return row
    }
    private func save(_ row: Components.Schemas.AdminRequest) -> Components.Schemas.AdminRequest {
        requestRecords[row.id] = row; statuses[row.id] = row.status; return row
    }
    func accept(id: Int, body: Components.Schemas.AcceptRequest) throws -> Components.Schemas.AdminRequest {
        var row = try request(id)
        guard row.status == "pending" else { throw changed() }
        let values = body.accepted_quantities ?? row.items.map { .init(item_id: $0.id, quantity: $0.requested_quantity) }
        guard Set(values.map(\.item_id)).count == values.count,
              values.allSatisfy({ value in row.items.contains { $0.id == value.item_id && value.quantity >= 0 && value.quantity <= $0.requested_quantity } }),
              values.contains(where: { $0.quantity > 0 }) else { throw changed() }
        row.items = row.items.map { initial in
            var item = initial; item.accepted_quantity = values.first { $0.item_id == item.id }?.quantity ?? 0; return item
        }
        row.status = "accepted"; return save(row)
    }
    func reject(id: Int, body: Components.Schemas.RejectRequest) throws -> Components.Schemas.AdminRequest {
        var row = try request(id)
        guard row.status == "pending", !body.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw changed() }
        row.status = "rejected"; row.rejection_reason = body.reason; return save(row)
    }
    func assignBox(id: Int, body: Components.Schemas.AssignBox) throws -> Components.Schemas.AdminRequest {
        let row = try request(id)
        guard row.status == "accepted", body.box_code == "DEMO-BOX" else { throw changed() }
        assignments.insert(id); return row
    }
    func issue(id: Int, body: Components.Schemas.IssueRequest) throws -> Components.Schemas.AdminRequest {
        var row = try request(id)
        if scenario == .issueConflict { throw APIError(status: 409, code: "issue_conflict", detail: String(localized: "The request changed before issue completed.")) }
        guard row.status == "accepted", assignments.contains(id), body.evidence_id > 0,
              row.items.contains(where: { $0.accepted_quantity > 0 }) else { throw changed() }
        row.items = row.items.map { initial in var item = initial; item.issued_quantity = item.accepted_quantity; return item }
        row.status = "issued"; row.issue_evidence_id = body.evidence_id; return save(row)
    }
    private func counts(_ resolution: Components.Schemas.ReturnItemResolution, remaining: Int) throws -> (returned: Int, damaged: Int, missing: Int, remaining: Int) {
        let returned = resolution.returned ?? 0, damaged = resolution.damaged ?? 0, missing = resolution.missing ?? 0
        var left = remaining
        for count in [returned, damaged, missing] {
            guard count >= 0, count <= left else { throw changed() }; left -= count
        }
        guard resolution.assets?.isEmpty != false else { throw changed() }
        return (returned, damaged, missing, left)
    }
    func returnRequest(id: Int, body: Components.Schemas.ReturnRequest) throws -> Components.Schemas.AdminRequest {
        var row = try request(id)
        guard row.status == "issued", body.evidence_id > 0, body.box_code == "DEMO-BOX",
              !body.remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(body.resolutions.map(\.item_id)).count == body.resolutions.count else { throw changed() }
        var recorded = false
        for resolution in body.resolutions {
            guard let index = row.items.firstIndex(where: { $0.id == resolution.item_id }),
                  let remaining = StaffMetadata.remaining(issued: row.items[index].issued_quantity, returned: row.items[index].returned_quantity,
                      damaged: row.items[index].damaged_quantity, missing: row.items[index].missing_quantity) else { throw changed() }
            let delta = try counts(resolution, remaining: remaining)
            row.items[index].returned_quantity += delta.returned; row.items[index].damaged_quantity += delta.damaged; row.items[index].missing_quantity += delta.missing
            recorded = recorded || delta.remaining < remaining
        }
        guard recorded else { throw changed() }
        row.return_evidence_ids += try JSONDecoder().decode(type(of: row.return_evidence_ids), from: Data("[\(body.evidence_id)]".utf8))
        row.status = row.items.allSatisfy { StaffMetadata.remaining(issued: $0.issued_quantity, returned: $0.returned_quantity, damaged: $0.damaged_quantity, missing: $0.missing_quantity) == 0 } ? "closed" : "issued"
        return save(row)
    }
    func resolveQR(body: Components.Schemas.QrResolve) throws -> Components.Schemas.QrResolveResult {
        guard ["DEMO-BOX", "DEMO-TOOL"].contains(body.payload) else { throw APIError(status: 404, code: "not_found", detail: String(localized: "Use DEMO-BOX or DEMO-TOOL in this sample.")) }
        var object = try JSONSerialization.jsonObject(with: Data(DebugStaffFixtures.qr.utf8)) as! [String: Any]
        var scopedQR = object["qr"] as! [String: Any]; scopedQR["makerspace"] = makerspaceID; object["qr"] = scopedQR
        if body.payload == "DEMO-TOOL" {
            var qr = object["qr"] as! [String: Any]; qr["id"] = 1202; qr["payload"] = body.payload; qr["target_type"] = "product"; qr["target_id"] = 901; object["qr"] = qr
            object["target"] = ["type": "product", "id": 901, "label": "Sample precision toolkit", "product_id": 901]
            object["allowed_actions"] = ["view", "direct_handout"]
        }
        return try decode(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    private func initialLoan() throws -> Components.Schemas.DirectLoan {
        if let saved = loanRecords[701] { return saved }
        let row: Components.Schemas.DirectLoan = try decode(DebugStaffFixtures.loan); loanRecords[row.id] = row; return row
    }
    func directLoans(page: Int) throws -> Components.Schemas.PaginatedDirectLoanList {
        try checked(); _ = try initialLoan()
        return try self.page(loanRecords.keys.sorted().compactMap { loanRecords[$0] }, page: page)
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
        try checked()
        let items = body.items ?? [], scans = body.qr_payloads ?? []
        guard body.borrower_id == 51, body.evidence_id > 0, body.container_id == nil,
              Set(items.map(\.product_id)).count == items.count,
              items.allSatisfy({ $0.product_id == 901 && (1...4).contains($0.quantity) }),
              Set(scans).count == scans.count, scans.allSatisfy({ $0 == "DEMO-TOOL" }),
              items.isEmpty || scans.isEmpty else { throw changed() }
        let quantity = items.first?.quantity ?? (scans.isEmpty ? 0 : 1)
        guard quantity > 0 else { throw changed() }
        var row = try initialLoan()
        row.id = nextLoanID; nextLoanID += 1
        row.public_token = String(format: "71000000-0000-4000-8000-%012lld", Int64(row.id))
        row.status = "active"; row.issue_evidence_id = body.evidence_id; row.return_evidence_id = nil; row.return_notes = ""
        row.items = [.init(product_name: row.target_label, quantity: quantity)]
        row.return_items = [.init(item_id: row.id * 100 + 1, product_name: row.target_label, remaining_quantity: quantity, tracking_mode: "quantity", assets: [])]
        loanRecords[row.id] = row; return row
    }
    func returnDirect(id: Int, body: Components.Schemas.DirectLoanReturn) throws -> Components.Schemas.DirectLoan {
        try checked(); _ = try initialLoan()
        guard var row = loanRecords[id], row.status == "active", body.evidence_id > 0,
              !body.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let resolutions = body.resolutions, Set(resolutions.map(\.item_id)).count == resolutions.count else { throw changed() }
        var recorded = false
        for resolution in resolutions {
            guard let index = row.return_items.firstIndex(where: { $0.item_id == resolution.item_id }) else { throw changed() }
            let remaining = row.return_items[index].remaining_quantity
            let delta = try counts(resolution, remaining: remaining)
            row.return_items[index].remaining_quantity = delta.remaining; recorded = recorded || delta.remaining < remaining
        }
        guard recorded else { throw changed() }
        row.return_notes = body.notes; row.return_evidence_id = body.evidence_id
        row.status = row.return_items.allSatisfy { $0.remaining_quantity == 0 } ? "returned" : "active"
        loanRecords[id] = row; return row
    }
    func evidence(body: Components.Schemas.EvidenceUrlRequest) async throws -> Components.Schemas.EvidenceUrlResponse {
        await beforeEvidence()
        try checked()
        if scenario == .uploadRefused { throw APIError(status: 403, code: "upload_refused", detail: String(localized: "The sample evidence upload was refused.")) }
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
        guard eventID == 801, body.checkin_token == "DEMO-EVENT" else { throw APIError(status: 404, code: "not_found", detail: String(localized: "That is not a check-in code for this event.")) }
        let status = attended ? "attended" : scenario == .waitlisted ? "waitlisted" : "registered"
        return try decode(DebugStaffFixtures.checkin, changes: ["status": status, "confirmable": status == "registered"])
    }
    func markAttended(registrationID: Int, body: Components.Schemas.EventAttendanceMark) throws -> Components.Schemas.EventRegistrationAdmin {
        try checked()
        if scenario == .attendanceConflict { throw APIError(status: 409, code: "changed", detail: String(localized: "This registration changed.")) }
        guard registrationID == 1101, !attended, scenario != .waitlisted else { throw APIError(status: 409, code: "changed", detail: String(localized: "This registration changed.")) }
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
        if scenario == .bookingConflict { throw APIError(status: 409, code: "changed", detail: String(localized: "This booking changed. Refresh its status.")) }
        return try decode(DebugStaffFixtures.booking, changes: ["status": bookingStatus])
    }
    func rejectBooking(id: Int) throws -> Components.Schemas.BookingAdmin { try checked(); bookingStatus = "rejected"; return try decode(DebugStaffFixtures.booking, changes: ["status": bookingStatus]) }
}
#endif
