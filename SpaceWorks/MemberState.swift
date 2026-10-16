import Foundation
import Observation
import SpaceWorksAPI

/// Generated models are retained intact; this protocol describes screen tasks, not a transport schema.
protocol MemberRepository: Sendable {
    var isDemo: Bool { get }
    func inventory(page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList
    func product(_ id: Int) async throws -> Components.Schemas.PublicProduct
    func categories() async throws -> [Components.Schemas.PublicCategory]
    func activity() async throws -> Components.Schemas.MemberActivity
    func bookings(page: Int) async throws -> Components.Schemas.MemberBookingList
    func events() async throws -> [Components.Schemas.PublicEvent]
    func spaces() async throws -> [Components.Schemas.PublicBookableSpace]
    func card() async throws -> Components.Schemas.OwnMemberCard
    func inbox(page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage
    func markRead(_ id: Int) async throws
    func markAllRead() async throws
    func unreadCount() async throws -> Int
}
extension MemberRepository { var isDemo: Bool { false } }

@MainActor @Observable
final class MemberState {
    enum Load: Equatable { case idle, loading, ready, failed(String) }
    let repository: any MemberRepository
    var search = ""
    var category: String?
    var unreadOnly = false
    private(set) var products: [Components.Schemas.PublicProduct] = []
    private(set) var categories: [Components.Schemas.PublicCategory] = []
    private(set) var activity: Components.Schemas.MemberActivity?
    private(set) var bookings: [Components.Schemas.MemberBooking] = []
    private(set) var events: [Components.Schemas.PublicEvent] = []
    private(set) var spaces: [Components.Schemas.PublicBookableSpace] = []
    private(set) var card: Components.Schemas.OwnMemberCard?
    private(set) var messages: [Components.Schemas.Inbox] = []
    private(set) var inventoryLoad = Load.idle
    private(set) var activityLoad = Load.idle
    private(set) var bookingsLoad = Load.idle
    private(set) var eventsLoad = Load.idle
    private(set) var spacesLoad = Load.idle
    private(set) var cardLoad = Load.idle
    private(set) var inboxLoad = Load.idle
    private(set) var inventoryHasMore = false
    private(set) var inboxHasMore = false
    private(set) var bookingsHasMore = false
    private(set) var inboxMutating = false
    private(set) var unreadCount: Int?
    private(set) var updated: [String: Date] = [:]
    private(set) var showGuidance: Bool
    private let settings: UserDefaults?
    private let guidanceKey: String?
    private var nextInventoryPage: Int?
    private var nextInboxPage: Int?
    private var nextBookingsPage: Int?
    private var bookingsGeneration = 0
    private var appliedSearch = ""
    private var appliedCategory: String?
    private var inventoryGeneration = 0
    private var inboxGeneration = 0
    private var active = true
    private var cardGeneration = 0

    init(repository: any MemberRepository, settings: UserDefaults? = nil, context: String? = nil) {
        self.repository = repository; self.settings = settings
        self.guidanceKey = context.map { "guidance.member-v1." + $0 }
        self.showGuidance = context.map { settings?.object(forKey: "guidance.member-v1." + $0) as? Bool ?? true } ?? true
    }
    func dismissGuidance() { showGuidance = false; if let guidanceKey { settings?.set(false, forKey: guidanceKey) } }
    func replayGuidance() { showGuidance = true; if let guidanceKey { settings?.set(true, forKey: guidanceKey) } }
    func invalidate() {
        active = false; inventoryGeneration += 1; inboxGeneration += 1; cardGeneration += 1
        products = []; categories = []; activity = nil; bookings = []; events = []; spaces = []; card = nil; messages = []; unreadCount = nil; updated = [:]
    }
    func loadHome() async {
        async let activity: Void = loadActivity()
        async let bookings: Void = loadBookings()
        async let events: Void = loadEvents()
        async let card: Void = loadCard()
        _ = await (activity, bookings, events, card)
    }
    func loadInventory(more: Bool = false) async {
        if more && (inventoryLoad == .loading || !inventoryHasMore) { return }
        if more && (search.trimmingCharacters(in: .whitespacesAndNewlines) != appliedSearch || category != appliedCategory) {
            await loadInventory(); return
        }
        inventoryGeneration += 1
        let generation = inventoryGeneration
        let page = more ? (nextInventoryPage ?? 1) : 1
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = category
        inventoryLoad = .loading
        if !more { products = [] }
        do {
            let result = try await repository.inventory(page: page, search: query, category: filter)
            guard active, generation == inventoryGeneration else { return }
            let next = try nextPage(result.next, after: page)
            var ids = Set<Int>()
            products = (more ? products + result.results : result.results).filter { ids.insert($0.id).inserted }
            nextInventoryPage = next; inventoryHasMore = next != nil; inventoryLoad = .ready
            appliedSearch = query; appliedCategory = filter
            updated["inventory"] = Date()
            if categories.isEmpty {
                let result = (try? await repository.categories()) ?? []
                guard active, generation == inventoryGeneration else { return }
                categories = result
            }
        } catch {
            guard active, generation == inventoryGeneration else { return }
            if discard(error) { products = []; updated["inventory"] = nil }
            inventoryLoad = .failed(APIError.display(error))
        }
    }
    func loadActivity() async {
        activityLoad = .loading
        do { let result = try await repository.activity(); guard active else { return }; activity = result; updated["activity"] = Date(); activityLoad = .ready }
        catch { guard active else { return }; if discard(error) { activity = nil; updated["activity"] = nil }; activityLoad = .failed(APIError.display(error)) }
    }
    func loadBookings(more: Bool = false) async {
        if more && (bookingsLoad == .loading || !bookingsHasMore) { return }
        bookingsGeneration += 1; let generation = bookingsGeneration
        let page = more ? (nextBookingsPage ?? 1) : 1
        bookingsLoad = .loading
        do {
            let result = try await repository.bookings(page: page)
            guard active, generation == bookingsGeneration else { return }
            let next = try nextPage(result.next, after: page)
            var tokens = Set<String>()
            bookings = (more ? bookings + result.results : result.results).filter { tokens.insert($0.public_token).inserted }
            nextBookingsPage = next; bookingsHasMore = next != nil; updated["bookings"] = Date(); bookingsLoad = .ready
        } catch {
            guard active, generation == bookingsGeneration else { return }
            if discard(error) { bookings = []; updated["bookings"] = nil }; bookingsLoad = .failed(APIError.display(error))
        }
    }
    func loadEvents() async {
        eventsLoad = .loading
        do { let result = try await repository.events(); guard active else { return }; events = result; updated["events"] = Date(); eventsLoad = .ready }
        catch { guard active else { return }; if discard(error) { events = []; updated["events"] = nil }; eventsLoad = .failed(APIError.display(error)) }
    }
    func loadSpaces() async {
        spacesLoad = .loading
        do { let result = try await repository.spaces(); guard active else { return }; spaces = result; spacesLoad = .ready }
        catch { guard active else { return }; spacesLoad = .failed(APIError.display(error)) }
    }
    func loadCard() async {
        cardGeneration += 1; let generation = cardGeneration
        card = nil; cardLoad = .loading
        do { let result = try await repository.card(); guard active, generation == cardGeneration else { return }; card = result; cardLoad = .ready }
        catch { guard active, generation == cardGeneration else { return }; card = nil; cardLoad = .failed(APIError.display(error)) }
    }
    func loadInbox(more: Bool = false) async {
        if more && (inboxLoad == .loading || !inboxHasMore) { return }
        inboxGeneration += 1; let generation = inboxGeneration
        let page = more ? (nextInboxPage ?? 1) : 1
        inboxLoad = .loading
        if !more { messages = [] }
        do {
            let result = try await repository.inbox(page: page, unread: unreadOnly)
            guard active, generation == inboxGeneration else { return }
            let next = try nextPage(result.next, after: page)
            var ids = Set<Int>()
            messages = (more ? messages + result.results : result.results).filter { ids.insert($0.id).inserted }
            nextInboxPage = next; inboxHasMore = next != nil; inboxLoad = .ready
            updated["inbox"] = Date()
            let count = try? await repository.unreadCount()
            guard active, generation == inboxGeneration else { return }
            unreadCount = count
        } catch {
            guard active, generation == inboxGeneration else { return }
            if discard(error) { messages = []; unreadCount = nil; updated["inbox"] = nil }
            inboxLoad = .failed(APIError.display(error))
        }
    }
    func loadUnreadCount() async {
        let count = try? await repository.unreadCount()
        guard active else { return }; unreadCount = count
    }
    func markRead(_ id: Int) async {
        guard !inboxMutating else { return }; inboxMutating = true; defer { inboxMutating = false }
        do { try await repository.markRead(id); guard active else { return }; await loadInbox() }
        catch { if active { inboxLoad = .failed(APIError.display(error)) } }
    }
    func markAllRead() async {
        guard !inboxMutating else { return }; inboxMutating = true; defer { inboxMutating = false }
        do { try await repository.markAllRead(); guard active else { return }; await loadInbox() }
        catch { if active { inboxLoad = .failed(APIError.display(error)) } }
    }
    private func discard(_ error: Error) -> Bool { [401, 403, 404].contains(APIError.status(error) ?? 0) }
    private func nextPage(_ next: String?, after current: Int) throws -> Int? {
        guard let next else { return nil }
        guard let components = URLComponents(string: next),
              let value = components.queryItems?.first(where: { $0.name == "page" })?.value,
              let page = Int(value), page > current else {
            throw APIError(status: 0, code: "invalid_next_page", detail: "The server returned an invalid next page.")
        }
        return page
    }
}
