import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

#if DEBUG
@MainActor final class MemberReadCooldownTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    func testReadTasksKeepIndependentRetryDeadlinesAndIssueNoRequestBeforeTheirDeadline() async {
        var now = start
        let end = start.addingTimeInterval(60)
        let repository = CooldownMemberRepository(deadline: end)
        await repository.fail(Set(["inventory", "categories", "activity", "bookings", "events", "spaces", "card", "inbox", "unread"]))
        let state = MemberState(repository: repository, now: { now })
        await allReads(state)
        await allReads(state)
        let blocked = await repository.counts
        for role in ["inventory", "categories", "activity", "bookings", "events", "spaces", "card", "inbox", "unread"] {
            XCTAssertEqual(blocked[role], 1, role)
            XCTAssertEqual(state.deadline(role), end, role)
            XCTAssertFalse(state.canLoad(role), role)
        }
        now = end.addingTimeInterval(1)
        await repository.fail([])
        await state.loadInventory(); await state.loadActivity(); await state.loadBookings(); await state.loadEvents()
        await state.loadSpaces(); await state.loadCard(); await state.loadInbox()
        let resumed = await repository.counts
        for role in ["inventory", "categories", "activity", "bookings", "events", "spaces", "card", "inbox", "unread"] {
            XCTAssertEqual(resumed[role], 2, role)
            XCTAssertTrue(state.canLoad(role), role)
        }
    }
    func testInboxReadAndMutationsShareCooldownAndCannotReplayThroughAnotherButton() async {
        var now = start
        let end = start.addingTimeInterval(60)
        let repository = CooldownMemberRepository(deadline: end)
        await repository.fail(["inbox"])
        let state = MemberState(repository: repository, now: { now })
        await state.loadInbox(); await state.markRead(1); await state.markAllRead()
        let first = await repository.counts
        XCTAssertEqual(first["inbox"], 1); XCTAssertNil(first["mark-read"]); XCTAssertNil(first["mark-all"])
        now = end.addingTimeInterval(1)
        await repository.fail(["mark-read"])
        await repository.setDeadline(now.addingTimeInterval(60))
        await state.markRead(1); await state.markAllRead(); await state.loadInbox()
        let second = await repository.counts
        XCTAssertEqual(second["mark-read"], 1); XCTAssertNil(second["mark-all"]); XCTAssertEqual(second["inbox"], 1)
    }
    func testInvalidationBlocksEveryReadAndMutationBeforeCallingTheRepository() async {
        let repository = CooldownMemberRepository(deadline: start.addingTimeInterval(60))
        let state = MemberState(repository: repository)
        state.invalidate()
        await allReads(state); await state.loadHome(); await state.markRead(1); await state.markAllRead()
        let calls = await repository.counts
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(state.retryDeadlines.isEmpty)
    }
    func testLateThrottledResponseAfterLogoutCannotPublishPrivateDataOrCooldown() async {
        let repository = CooldownMemberRepository(deadline: start.addingTimeInterval(60))
        await repository.deferActivity()
        await repository.fail(["activity"])
        let state = MemberState(repository: repository, now: { self.start })
        let pending = Task { await state.loadActivity() }
        await repository.waitForActivity()
        state.invalidate()
        await repository.releaseActivity()
        await pending.value
        XCTAssertNil(state.activity)
        XCTAssertNil(state.deadline("activity"))
        await state.loadActivity()
        let count = await repository.counts["activity"]
        XCTAssertEqual(count, 1)
    }
    func testThrottledRefreshRetainsPreviouslyLoadedActivityAndItsTimestamp() async {
        let repository = CooldownMemberRepository(deadline: start.addingTimeInterval(60))
        let state = MemberState(repository: repository, now: { self.start })
        await state.loadActivity()
        XCTAssertNotNil(state.activity)
        let stamp = state.updated["activity"]
        await repository.fail(["activity"])
        await state.loadActivity()
        XCTAssertNotNil(state.activity)
        XCTAssertEqual(state.updated["activity"], stamp)
        XCTAssertEqual(state.activityLoad, .failed("Please wait."))
        await state.loadActivity()
        let count = await repository.counts["activity"]
        XCTAssertEqual(count, 2)
    }
    func testCategoryThrottleDoesNotFailInventoryOrRetryHiddenFilterFetchOnEverySearch() async {
        let repository = CooldownMemberRepository(deadline: start.addingTimeInterval(60))
        await repository.fail(["categories"])
        let state = MemberState(repository: repository, now: { self.start })
        await state.loadInventory()
        XCTAssertEqual(state.inventoryLoad, .ready)
        XCTAssertEqual(state.categoriesLoad, .failed("Please wait."))
        state.search = "drill"
        await state.loadInventory()
        let calls = await repository.counts
        XCTAssertEqual(calls["inventory"], 2); XCTAssertEqual(calls["categories"], 1)
        XCTAssertNotNil(state.deadline("categories"))
    }
    func testUnreadCounterThrottleIsNotSilentlyRetriedBySuccessfulInboxRefresh() async {
        let repository = CooldownMemberRepository(deadline: start.addingTimeInterval(60))
        await repository.fail(["unread"])
        let state = MemberState(repository: repository, now: { self.start })
        await state.loadUnreadCount(); await state.loadInbox(); await state.loadInbox()
        let calls = await repository.counts
        XCTAssertEqual(calls["unread"], 1); XCTAssertEqual(calls["inbox"], 2)
        XCTAssertEqual(state.inboxLoad, .ready)
    }
    private func allReads(_ state: MemberState) async {
        await state.loadInventory(); await state.loadCategories(); await state.loadActivity(); await state.loadBookings()
        await state.loadEvents(); await state.loadSpaces(); await state.loadCard(); await state.loadInbox(); await state.loadUnreadCount()
    }
}

private actor CooldownMemberRepository: MemberRepository {
    private let demo = DemoMemberRepository()
    private var failures = Set<String>()
    private var deadline: Date
    private(set) var counts: [String: Int] = [:]
    private var delayedActivity = false
    private var activityStarted = false
    private var activityWait: CheckedContinuation<Void, Never>?
    private var startWait: CheckedContinuation<Void, Never>?
    init(deadline: Date) { self.deadline = deadline }
    func fail(_ roles: Set<String>) { failures = roles }
    func setDeadline(_ value: Date) { deadline = value }
    func deferActivity() { delayedActivity = true }
    func waitForActivity() async { if !activityStarted { await withCheckedContinuation { startWait = $0 } } }
    func releaseActivity() { activityWait?.resume(); activityWait = nil }
    private func called(_ role: String) throws {
        counts[role, default: 0] += 1
        if failures.contains(role) { throw APIError(status: 429, code: "throttled", detail: "Please wait.", retryAfter: deadline) }
    }
    func inventory(page: Int, search: String, category: String?) async throws -> Components.Schemas.PaginatedPublicProductList {
        try called("inventory"); return try await demo.inventory(page: page, search: search, category: category)
    }
    func product(_ id: Int) async throws -> Components.Schemas.PublicProduct { try called("product"); return try await demo.product(id) }
    func categories() async throws -> [Components.Schemas.PublicCategory] { try called("categories"); return try await demo.categories() }
    func activity() async throws -> Components.Schemas.MemberActivity {
        if delayedActivity { activityStarted = true; startWait?.resume(); startWait = nil; await withCheckedContinuation { activityWait = $0 } }
        try called("activity"); return try await demo.activity()
    }
    func bookings(page: Int) async throws -> Components.Schemas.MemberBookingList { try called("bookings"); return try await demo.bookings(page: page) }
    func events() async throws -> [Components.Schemas.PublicEvent] { try called("events"); return try await demo.events() }
    func spaces() async throws -> [Components.Schemas.PublicBookableSpace] { try called("spaces"); return try await demo.spaces() }
    func card() async throws -> Components.Schemas.OwnMemberCard { try called("card"); return try await demo.card() }
    func inbox(page: Int, unread: Bool) async throws -> Components.Schemas.InboxPage { try called("inbox"); return try await demo.inbox(page: page, unread: unread) }
    func markRead(_ id: Int) async throws { try called("mark-read"); try await demo.markRead(id) }
    func markAllRead() async throws { try called("mark-all"); try await demo.markAllRead() }
    func unreadCount() async throws -> Int { try called("unread"); return try await demo.unreadCount() }
}
#endif
