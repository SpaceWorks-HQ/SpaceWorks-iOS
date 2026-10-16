import Foundation

extension SpaceWorksService {
    public func memberInventory(slug: String, page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList {
        try await client.api_v1_public_inventory_list(.init(path: .init(makerspace_slug: slug),
            query: .init(category: category, page: page, q: search.isEmpty ? nil : search))).ok.body.json
    }
    public func memberProduct(slug: String, id: Int) async throws -> Components.Schemas.PublicProduct {
        try await client.api_v1_public_inventory_retrieve(.init(path: .init(id: id, makerspace_slug: slug))).ok.body.json
    }
    public func memberCategories(slug: String) async throws -> [Components.Schemas.PublicCategory] {
        try await client.api_v1_public_inventory_categories_list(.init(path: .init(makerspace_slug: slug))).ok.body.json
    }
    public func memberActivity(id: Int) async throws -> Components.Schemas.MemberActivity {
        try await client.api_v1_member_makerspaces_activity_retrieve(.init(path: .init(makerspace_id: id))).ok.body.json
    }
    public func memberBookings(slug: String, page: Int) async throws -> Components.Schemas.MemberBookingList {
        try await client.api_v1_public_my_bookings_retrieve(.init(path: .init(makerspace_slug: slug), query: .init(page: page, period: .upcoming))).ok.body.json
    }
    public func memberEvents(slug: String) async throws -> [Components.Schemas.PublicEvent] {
        try await client.api_v1_public_events_list(.init(path: .init(makerspace_slug: slug))).ok.body.json
    }
    public func memberEvent(slug: String, token: String) async throws -> Components.Schemas.PublicEvent {
        try await client.api_v1_public_events_retrieve(.init(path: .init(makerspace_slug: slug, public_token: token))).ok.body.json
    }
    public func memberSpaces(slug: String) async throws -> [Components.Schemas.PublicBookableSpace] {
        try await client.api_v1_public_spaces_list(.init(path: .init(makerspace_slug: slug))).ok.body.json
    }
    public func memberCard(id: Int) async throws -> Components.Schemas.OwnMemberCard {
        try await client.api_v1_member_makerspaces_member_card_retrieve(.init(path: .init(makerspace_id: id))).ok.body.json
    }
    public func memberInbox(id: Int, page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage {
        try await client.api_v1_notifications_inbox_retrieve(.init(path: .init(makerspace_id: id), query: .init(page: page, unread: unread))).ok.body.json
    }
    public func memberMarkRead(id: Int, message: Int) async throws {
        _ = try await client.api_v1_notifications_inbox_read_create(.init(path: .init(id: message, makerspace_id: id))).ok.body.json
    }
    public func memberMarkAllRead(id: Int) async throws {
        _ = try await client.api_v1_notifications_inbox_read_all_create(.init(path: .init(makerspace_id: id))).ok.body.json
    }
    public func memberUnreadCount(id: Int) async throws -> Components.Schemas.Count {
        try await client.api_v1_notifications_inbox_unread_count_retrieve(.init(path: .init(makerspace_id: id))).ok.body.json
    }
}
