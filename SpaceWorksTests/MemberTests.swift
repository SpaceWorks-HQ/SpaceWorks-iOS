import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class MemberTests: XCTestCase {
    func testGeneratedDemoFixturesPopulateHomeAndSupportInventoryPaginationAndFilters() async throws {
        let repository = DemoMemberRepository()
        let state = MemberState(repository: repository)
        await state.loadHome()
        XCTAssertEqual(state.activityLoad, .ready); XCTAssertEqual(state.bookingsLoad, .ready)
        XCTAssertEqual(state.eventsLoad, .ready); XCTAssertEqual(state.cardLoad, .ready)
        XCTAssertEqual(state.card?.printed_name, "Meera Nair"); XCTAssertFalse(state.bookings.isEmpty)
        await state.loadInventory(); XCTAssertEqual(state.products.count, 6); XCTAssertTrue(state.inventoryHasMore)
        await state.loadInventory(more: true); XCTAssertEqual(state.products.count, 12); XCTAssertFalse(state.inventoryHasMore)
        state.search = "multimeter"; await state.loadInventory()
        XCTAssertEqual(state.products.count, 1); XCTAssertEqual(state.products.first?.name, "Digital multimeter")
        state.search = "no match"; await state.loadInventory(); XCTAssertTrue(state.products.isEmpty)
        XCTAssertEqual(state.inventoryLoad, .ready)
        let spaces = try await repository.spaces(); XCTAssertFalse(spaces.isEmpty)
    }
    func testInboxReadActionsRefreshServerConfirmedState() async {
        let state = MemberState(repository: DemoMemberRepository())
        state.unreadOnly = true; await state.loadInbox()
        XCTAssertEqual(state.messages.count, 1); XCTAssertEqual(state.unreadCount, 1)
        await state.markRead(state.messages[0].id)
        XCTAssertTrue(state.messages.isEmpty); XCTAssertEqual(state.unreadCount, 0)
        state.unreadOnly = false; await state.loadInbox()
        XCTAssertEqual(state.messages.count, 2); XCTAssertTrue(state.messages.allSatisfy { $0.read_at != nil })
        await state.markAllRead(); XCTAssertEqual(state.unreadCount, 0)
    }
    func testEmptyErrorAndRevokedCardStatesRemainDistinct() async {
        let empty = MemberState(repository: DemoMemberRepository(scenario: .empty))
        await empty.loadHome(); await empty.loadInventory(); await empty.loadInbox()
        XCTAssertEqual(empty.inventoryLoad, .ready); XCTAssertTrue(empty.products.isEmpty)
        XCTAssertTrue(empty.bookings.isEmpty); XCTAssertTrue(empty.events.isEmpty)
        XCTAssertNil(empty.card)
        if case .failed = empty.cardLoad {} else { XCTFail("Not-issued card must not render an active QR") }
        let offline = MemberState(repository: DemoMemberRepository(scenario: .offline))
        await offline.loadHome()
        if case .failed = offline.activityLoad {} else { XCTFail("Transport failure must not become empty success") }
        XCTAssertNil(offline.activity); XCTAssertNil(offline.card)
        let revoked = MemberState(repository: DemoMemberRepository(scenario: .revokedCard))
        await revoked.loadCard(); XCTAssertEqual(revoked.card?.is_active, false); XCTAssertEqual(revoked.card?.qr_active, false)
    }
    func testInvalidationPreventsLateCardFromReappearing() async throws {
        let gate = CardGate()
        let state = MemberState(repository: GatedMemberRepository(gate: gate))
        let pending = Task { await state.loadCard() }
        await gate.waitUntilRequested()
        state.invalidate()
        await gate.resolve(try await DemoMemberRepository().card())
        await pending.value
        XCTAssertNil(state.card); XCTAssertTrue(state.products.isEmpty); XCTAssertNil(state.unreadCount)
    }
    func testLatestCardRefusalWinsOverEarlierSuccessfulRequest() async throws {
        let gate = CardGate()
        let state = MemberState(repository: GatedMemberRepository(gate: gate))
        let first = Task { await state.loadCard() }
        await gate.waitUntilRequested()
        await state.loadCard()
        await gate.resolve(try await DemoMemberRepository().card()); await first.value
        XCTAssertNil(state.card)
        if case .failed = state.cardLoad {} else { XCTFail("Late success must not resurrect a refused QR") }
    }
    func testGuidanceIsScopedToAccountAndMakerspaceAndDemoStaysInMemory() {
        let settings = UserDefaults(suiteName: UUID().uuidString)!
        let first = MemberState(repository: DemoMemberRepository(), settings: settings, context: "server/account/space7")
        first.dismissGuidance()
        let restored = MemberState(repository: DemoMemberRepository(), settings: settings, context: "server/account/space7")
        XCTAssertFalse(restored.showGuidance)
        let other = MemberState(repository: DemoMemberRepository(), settings: settings, context: "server/account/space9")
        XCTAssertTrue(other.showGuidance)
        let demo = MemberState(repository: DemoMemberRepository()); demo.dismissGuidance()
        XCTAssertTrue(MemberState(repository: DemoMemberRepository()).showGuidance)
    }
}

private actor CardGate {
    private var pending: CheckedContinuation<Components.Schemas.OwnMemberCard, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    private var requested = false
    func card() async throws -> Components.Schemas.OwnMemberCard {
        if requested { throw APIError(status: 403, code: "card_revoked", detail: "Your card is no longer active.") }
        requested = true
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation; observer?.resume(); observer = nil
        }
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resolve(_ card: Components.Schemas.OwnMemberCard) { pending?.resume(returning: card); pending = nil }
}

private struct GatedMemberRepository: MemberRepository {
    let gate: CardGate
    let base = DemoMemberRepository()
    func inventory(page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList { try await base.inventory(page: page, search: search, category: category) }
    func product(_ id: Int) async throws -> Components.Schemas.PublicProduct { try await base.product(id) }
    func categories() async throws -> [Components.Schemas.PublicCategory] { try await base.categories() }
    func activity() async throws -> Components.Schemas.MemberActivity { try await base.activity() }
    func bookings(page: Int) async throws -> Components.Schemas.MemberBookingList { try await base.bookings(page: page) }
    func events() async throws -> [Components.Schemas.PublicEvent] { try await base.events() }
    func spaces() async throws -> [Components.Schemas.PublicBookableSpace] { try await base.spaces() }
    func card() async throws -> Components.Schemas.OwnMemberCard { try await gate.card() }
    func inbox(page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage { try await base.inbox(page: page, unread: unread) }
    func markRead(_ id: Int) async throws { try await base.markRead(id) }
    func markAllRead() async throws { try await base.markAllRead() }
    func unreadCount() async throws -> Int { try await base.unreadCount() }
}
