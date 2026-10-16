#if DEBUG
import Foundation
import SpaceWorksAPI

actor DemoMemberRepository: MemberRepository {
    nonisolated let isDemo = true
    enum Scenario: String, CaseIterable, Sendable { case populated = "Populated", empty = "Empty", offline = "Error", revokedCard = "Revoked card" }
    let scenario: Scenario
    let name: String
    private var readIDs = Set<Int>()
    init(scenario: Scenario = .populated, name: String = "Meera Nair") { self.scenario = scenario; self.name = name }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }
    func inventory(page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList {
        var object = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.inventory.utf8)) as! [String: Any]
        let all = (object["results"] as! [[String: Any]]).filter { item in
            (search.isEmpty || (item["name"] as! String).localizedCaseInsensitiveContains(search)) &&
            (category == nil || item["category_slug"] as? String == category)
        }
        let rows = scenario == .empty ? [] : Array(all.dropFirst(max(0, page - 1) * 6).prefix(6))
        object["results"] = rows; object["count"] = scenario == .empty ? 0 : all.count
        if scenario != .empty && page * 6 < all.count { object["next"] = "/api/v1/public/fab-lab-kochi/inventory/?page=\(page + 1)" }
        else { object["next"] = NSNull() }
        return try decode(Components.Schemas.PaginatedPublicProductList.self, String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func product(_ id: Int) async throws -> Components.Schemas.PublicProduct {
        let inventory = try decode(Components.Schemas.PaginatedPublicProductList.self, DebugMemberFixtures.inventory)
        guard let product = inventory.results.first(where: { $0.id == id }) else { throw APIError(status: 404, code: "not_found", detail: "This item is no longer available.") }
        return product
    }
    func categories() async throws -> [Components.Schemas.PublicCategory] { try decode([Components.Schemas.PublicCategory].self, DebugMemberFixtures.categories) }
    func activity() async throws -> Components.Schemas.MemberActivity {
        var object = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.activity.utf8)) as! [String: Any]
        if scenario == .empty {
            for key in ["active_hardware_loans", "request_history", "loan_history", "event_registrations", "notices"] { object[key] = [] }
            object["membership_dues"] = ["dues_amount": "0", "outstanding_by_currency": [String: String]()] as [String: Any]
        }
        return try decode(Components.Schemas.MemberActivity.self, String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func bookings(page: Int) async throws -> Components.Schemas.MemberBookingList {
        try decode(Components.Schemas.MemberBookingList.self, scenario == .empty ? #"{"count":0,"next":null,"previous":null,"results":[]}"# : DebugMemberFixtures.bookings)
    }
    func events() async throws -> [Components.Schemas.PublicEvent] { try decode([Components.Schemas.PublicEvent].self, scenario == .empty ? "[]" : DebugMemberFixtures.events) }
    func spaces() async throws -> [Components.Schemas.PublicBookableSpace] { try decode([Components.Schemas.PublicBookableSpace].self, scenario == .empty ? "[]" : DebugMemberFixtures.spaces) }
    func card() async throws -> Components.Schemas.OwnMemberCard {
        if scenario == .empty { throw APIError(status: 404, code: "not_issued", detail: "A membership card hasn't been issued yet.") }
        var object = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.card.utf8)) as! [String: Any]
        object["printed_name"] = name
        if scenario == .revokedCard { object["is_active"] = false; object["qr_active"] = false }
        return try decode(Components.Schemas.OwnMemberCard.self, String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func inbox(page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage {
        var object = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.inbox.utf8)) as! [String: Any]
        var rows = object["results"] as! [[String: Any]]
        for index in rows.indices where readIDs.contains(rows[index]["id"] as! Int) { rows[index]["read_at"] = "2026-10-16T10:00:00Z" }
        if unread { rows = rows.filter { $0["read_at"] is NSNull } }
        if scenario == .empty { rows = [] }
        object["results"] = rows; object["count"] = rows.count
        return try decode(Components.Schemas.InboxPage.self, String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    func markRead(_ id: Int) async throws { if scenario == .offline { throw URLError(.notConnectedToInternet) }; readIDs.insert(id) }
    func markAllRead() async throws {
        let page = try await inbox(page: 1, unread: false)
        readIDs.formUnion(page.results.map(\.id))
    }
    func unreadCount() async throws -> Int { try await inbox(page: 1, unread: true).results.count }
}
#endif
