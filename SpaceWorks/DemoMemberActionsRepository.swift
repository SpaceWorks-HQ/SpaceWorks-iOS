#if DEBUG
import Foundation
import SpaceWorksAPI

/// All mutations are in-memory sample records; nothing crosses a URLSession or SDK boundary.
actor DemoMemberStore {
    var activityJSON = DebugMemberFixtures.activity
    var bookingsJSON = DebugMemberFixtures.bookings
    func activity() -> String { activityJSON }
    func bookings() -> String { bookingsJSON }
    func request(_ count: Int) throws {
        var value = try object(activityJSON)
        var rows = value["request_history"] as? [[String: Any]] ?? []
        rows.insert(["status": "pending", "created_at": ISO8601DateFormatter().string(from: Date()), "item_count": count,
                     "returned_quantity": 0, "damaged_quantity": 0, "missing_quantity": 0], at: 0)
        value["request_history"] = rows; activityJSON = try json(value)
    }
    func renewed(_ request: Int, due: Date) throws -> Int {
        var value = try object(activityJSON)
        var rows = value["active_hardware_loans"] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["request_id"] as? Int == request }) else { throw APIError(status: 404, code: "demo_not_found", detail: "This loan wasn't found.") }
        rows[index]["due_at"] = ISO8601DateFormatter().string(from: due); rows[index]["renewal_count"] = (rows[index]["renewal_count"] as? Int ?? 0) + 1
        value["active_hardware_loans"] = rows; activityJSON = try json(value)
        return rows[index]["renewal_count"] as? Int ?? 1
    }
    func booked(_ input: Components.Schemas.PublicBookingInput, status: String) throws {
        var value = try object(bookingsJSON); var rows = value["results"] as? [[String: Any]] ?? []
        let format = ISO8601DateFormatter()
        rows.insert(["public_token": UUID().uuidString, "space_name": "Workshop bench", "timezone": "Asia/Kolkata", "starts_at": format.string(from: input.starts_at),
                     "ends_at": format.string(from: input.ends_at), "status": status, "cancellation_cutoff_at": format.string(from: input.starts_at), "can_cancel": true], at: 0)
        value["results"] = rows; value["count"] = rows.count; bookingsJSON = try json(value)
    }
    func registered(status: String) throws {
        var value = try object(activityJSON)
        var rows = value["event_registrations"] as? [[String: Any]] ?? []
        rows.removeAll { $0["registration_id"] as? Int == 777 }
        rows.insert(["registration_id": 777, "checkin_token": status == "registered" ? UUID().uuidString as Any : NSNull(), "event_title": "Make your first circuit",
                     "starts_at": "2026-10-20T09:00:00Z", "ends_at": "2026-10-20T11:00:00Z", "status": status, "cancellation_cutoff_at": "2026-10-20T08:00:00Z",
                     "can_cancel": true, "waitlist_position": status == "waitlisted" ? 3 as Any : NSNull(), "feedback_available": false, "feedback_path": NSNull(), "certificate": NSNull()], at: 0)
        value["event_registrations"] = rows; activityJSON = try json(value)
    }
    func cancelBooking(_ token: String) throws -> Components.Schemas.MemberBooking {
        var value = try object(bookingsJSON); var rows = value["results"] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["public_token"] as? String == token }), rows[index]["can_cancel"] as? Bool == true else { throw APIError(status: 409, code: "demo_booking_conflict", detail: "This booking can no longer be cancelled.") }
        rows[index]["status"] = "cancelled"; rows[index]["can_cancel"] = false; value["results"] = rows; bookingsJSON = try json(value)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Components.Schemas.MemberBooking.self, from: JSONSerialization.data(withJSONObject: rows[index]))
    }
    func cancelled(_ id: Int) throws {
        var value = try object(activityJSON); var rows = value["event_registrations"] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["registration_id"] as? Int == id }) else { throw APIError(status: 404, code: "demo_not_found", detail: "This registration wasn't found.") }
        rows[index]["status"] = "cancelled"; rows[index]["checkin_token"] = NSNull(); rows[index]["can_cancel"] = false
        value["event_registrations"] = rows; activityJSON = try json(value)
    }
    private func object(_ value: String) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any] }
    private func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
}

actor DemoMemberActionsRepository: MemberActionsRepository {
    enum Scenario: String, CaseIterable { case success = "Success", refused = "Refused", conflict = "Conflict", throttled = "Rate limited", pending = "Awaiting approval", waitlisted = "Waitlisted" }
    let store: DemoMemberStore
    private let bootstrapJSON: String
    private(set) var scenario: Scenario
    private var receipts: [String: (Data, Components.Schemas.RequestSubmitResponse)] = [:]
    private var savedProfile: Components.Schemas.AccountProfile
    private var savedPreferences = Components.Schemas.PreferenceResponse(cells: [
        .init(feature: .hardware_requests, channel: .email, enabled: true, daily_digest: false, available: true, mandatory_events: ["loan_overdue"]),
        .init(feature: .events, channel: .in_app, enabled: true, available: true, mandatory_events: []),
        .init(feature: .events, channel: .native_push, enabled: false, available: false, mandatory_events: [])
    ])
    init(store: DemoMemberStore = DemoMemberStore(), scenario: Scenario = .success, name: String = "Meera Nair", bootstrapJSON: String = DebugMemberFixtures.bootstrap) {
        self.store = store; self.scenario = scenario; self.bootstrapJSON = bootstrapJSON
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        savedProfile = .init(display_name: name, first_name: parts.first ?? name, last_name: parts.count > 1 ? parts[1] : "", phone: "")
    }
    func preview(_ scenario: Scenario) { self.scenario = scenario }
    private func check() throws {
        switch scenario {
        case .refused: throw APIError(status: 403, code: "demo_refused", detail: "This action isn't available for your membership.")
        case .conflict: throw APIError(status: 409, code: "demo_conflict", detail: "This changed. Refresh and try again.")
        case .throttled: throw APIError(status: 429, code: "demo_throttled", detail: "Too many requests. Try again later.", retryAfter: Date().addingTimeInterval(5))
        default: break
        }
    }
    func bootstrap() async throws -> Components.Schemas.TenantBootstrap {
        return try JSONDecoder().decode(Components.Schemas.TenantBootstrap.self, from: Data(bootstrapJSON.utf8))
    }
    func submit(items: [Components.Schemas.RequestItemInput], purpose: String, key: String) async throws -> Components.Schemas.RequestSubmitResponse {
        try check()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(Components.Schemas.RequestSubmit(requested_for: purpose, items: items))
        if let existing = receipts[key] {
            guard existing.0 == payload else { throw APIError(status: 409, code: "idempotency_conflict", detail: "This request changed. Review it again.") }
            return existing.1
        }
        let result = Components.Schemas.RequestSubmitResponse(public_token: UUID().uuidString, status: "pending")
        receipts[key] = (payload, result); try await store.request(items.reduce(0) { $0 + $1.quantity }); return result
    }
    func renew(request: Int) async throws -> Components.Schemas.LoanRenewal {
        try check(); let due = Date().addingTimeInterval(14 * 86400)
        let count = try await store.renewed(request, due: due); return .init(id: request, return_due_at: due, renewal_count: count)
    }
    func availability(space: String, start: Date, end: Date) async throws -> Components.Schemas.PublicSpaceAvailability {
        try check(); return .init(public_token: space, starts_at: start, ends_at: end, timezone: "Asia/Kolkata", opening_intervals: [.init(starts_at: start, ends_at: end)], availability: [])
    }
    func book(space: String, input: Components.Schemas.PublicBookingInput) async throws -> Components.Schemas.PublicBookingResponse {
        try check(); let status: Components.Schemas.PublicBookingResponseStatusEnum = scenario == .pending ? .pending : .confirmed
        try await store.booked(input, status: status.rawValue); return .init(status: .init(value1: status))
    }
    func cancelBooking(token: String) async throws -> Components.Schemas.MemberBooking { try check(); return try await store.cancelBooking(token) }
    func register(event: String, input: Components.Schemas.PublicEventRegistrationInput) async throws -> Components.Schemas.PublicEventRegistrationResponse {
        try check(); let status: Components.Schemas.PublicEventRegistrationResponseStatusEnum = scenario == .waitlisted ? .waitlisted : scenario == .pending ? .pending_approval : .registered
        try await store.registered(status: status.rawValue); return .init(status: .init(value1: status))
    }
    func cancelEvent(registration: Int) async throws -> Components.Schemas.MemberRegistrationCancelResponse {
        try check(); try await store.cancelled(registration); return .init(status: .init(value1: .cancelled))
    }
    func eventQR(registration: Int) async throws -> Data {
        try check()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let json = await store.activity()
        let activity = try decoder.decode(Components.Schemas.MemberActivity.self, from: Data(json.utf8))
        guard activity.event_registrations?.contains(where: { $0.registration_id == registration && $0.status == "registered" }) == true else {
            throw APIError(status: 403, code: "demo_ticket_unavailable", detail: "A ticket is available only after registration is confirmed.")
        }
        return Data(#"<svg viewBox="0 0 8 8"><path d="M2 2h2v2H2z"/></svg>"#.utf8)
    }
    func profile() async throws -> Components.Schemas.AccountProfile { try check(); return savedProfile }
    func updateProfile(_ input: Components.Schemas.PatchedAccountProfile) async throws -> Components.Schemas.AccountProfile {
        try check(); savedProfile = .init(display_name: input.display_name ?? savedProfile.display_name, first_name: input.first_name ?? savedProfile.first_name,
            last_name: input.last_name ?? savedProfile.last_name, phone: input.phone ?? savedProfile.phone); return savedProfile
    }
    func preferences() async throws -> Components.Schemas.PreferenceResponse { try check(); return savedPreferences }
    func updatePreference(_ input: Components.Schemas.PatchedPreferenceWrite) async throws -> Components.Schemas.PreferenceResponse {
        try check()
        guard let index = savedPreferences.cells.firstIndex(where: { $0.feature == input.feature && $0.channel == input.channel }) else { throw APIError(status: 404, code: "demo_not_found", detail: "This option wasn't found.") }
        var cell = savedPreferences.cells[index]
        if let enabled = input.enabled {
            guard !enabled || cell.available else { throw APIError(status: 400, code: "demo_unavailable", detail: "This option isn't available in this makerspace.") }
            cell.enabled = enabled
        }
        if let daily = input.daily_digest { cell.daily_digest = daily }
        savedPreferences.cells[index] = cell; return savedPreferences
    }
}
#endif
