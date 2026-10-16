#if DEBUG
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class NotificationAuthTests: XCTestCase {
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    func testForegroundHintRevalidatesCurrentScopeAndNeverSwitchesForAnotherMakerspace() async throws {
        let counter = ForegroundIdentityCounter()
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/me" { counter.increment(); return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.user.utf8)) }
            return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.config.utf8))
        }; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let state = AuthState(origin: try ServerOrigin("https://auth.example"), session: DeviceSession.make(configuration: configuration), settings: UserDefaults(suiteName: UUID().uuidString)!, storage: NotificationAuthStorage())
        await state.restore(); await state.select(7); let baseline = counter.value
        state.queueForegroundHint(try XCTUnwrap(NotificationHint(payload: ["makerspace_id": "8"])))
        await state.processForegroundHint(); XCTAssertEqual(counter.value, baseline); XCTAssertEqual(state.selectedID, 7)
        state.queueForegroundHint(try XCTUnwrap(NotificationHint(payload: ["makerspace_id": "7"])))
        await state.processForegroundHint()
        XCTAssertEqual(counter.value, baseline + 1); XCTAssertEqual(state.selectedID, 7)
        XCTAssertEqual(state.inboxRefreshRevision, 1); XCTAssertEqual(state.inboxRefreshMakerspaceID, 7)
        await state.invalidateSession(message: "Signed out.")
    }
    func testProtectedIdentityAndHoldersClearBeforeDelayedAuthorizedPushCleanupAndTokenWipe() async throws {
        let gate = IdentityResponseGate(); defer { gate.release() }
        let origin = try ServerOrigin("https://cleanup-" + UUID().uuidString.lowercased() + ".example")
        let identity = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DebugAuthFixtures.user.utf8)) as? [String: Any])
        let accountID = try XCTUnwrap(identity["id"] as? Int)
        let vault = PushRegistrationVault(origin: origin, accountID: accountID)
        try vault.store(.init(enabled: false, registrations: [.init(makerspaceID: 7, deviceID: 701, tokenDigest: String(repeating: "a", count: 64), environment: "development")]))
        defer { try? vault.remove() }
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/integrations/push/devices/701")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
                gate.wait(); return (204, [:], Data())
            }
            let body = request.url?.path == "/api/v1/auth/me" ? DebugAuthFixtures.user : DebugAuthFixtures.config
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let storage = NotificationAuthStorage()
        let state = AuthState(origin: origin, session: DeviceSession.make(configuration: configuration), settings: UserDefaults(suiteName: UUID().uuidString)!, storage: storage)
        await state.restore(); await state.select(7)
        var cleared = false; state.registerPrivateHolder(UUID()) { cleared = true }
        let ending = Task { await state.invalidateSession(message: "Signed out.") }
        for _ in 0..<500 { if gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        guard gate.entered else { gate.release(); await ending.value; XCTFail("Owned cleanup never started"); return }
        XCTAssertTrue(cleared); XCTAssertNil(state.user); XCTAssertTrue(state.memberships.isEmpty); XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.stage, .signIn); XCTAssertTrue(state.busy); XCTAssertTrue(state.endingSession)
        XCTAssertNotNil(storage.load(), "Owned cleanup must finish before credentials are removed")
        state.username = "new account"; state.password = "blocked"; await state.signIn(); XCTAssertNil(state.user)
        gate.release(); await ending.value
        XCTAssertFalse(state.busy); XCTAssertFalse(state.endingSession); XCTAssertNil(storage.load()); XCTAssertTrue(try vault.load().registrations.isEmpty)
    }
    func testConcurrentRoutingAndRegistrationShareFreshIdentityBeforeEveryWaiterContinues() async throws {
        let gate = IdentityResponseGate(); defer { gate.release() }
        let counter = ForegroundIdentityCounter()
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/me" {
                counter.increment(); if counter.value > 1 { gate.wait() }
                return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.user.utf8))
            }
            return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.config.utf8))
        }; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let state = AuthState(origin: try ServerOrigin("https://identity-coalesced.example"), session: DeviceSession.make(configuration: configuration), settings: UserDefaults(suiteName: UUID().uuidString)!, storage: NotificationAuthStorage())
        await state.restore(); await state.select(7)
        let tasks = (0..<12).map { _ in Task { @MainActor in
            let ids = try await state.freshMembershipIDs()
            XCTAssertFalse(state.busy); XCTAssertEqual(state.stage, .signedIn)
            return ids
        } }
        for _ in 0..<500 { if gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        guard gate.entered else { gate.release(); for task in tasks { _ = try? await task.value }; XCTFail("Fresh identity was never requested"); return }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(counter.value, 2); gate.release()
        for task in tasks { let ids = try await task.value; XCTAssertEqual(ids, [7, 8]) }
        XCTAssertEqual(counter.value, 2)
        await state.invalidateSession(message: "Signed out.")
    }
    func testOldIdentityResponseCannotRestoreProtectedUIAfterLocalInvalidation() async throws {
        let gate = IdentityResponseGate(); defer { gate.release() }
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/me" { gate.wait(); return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.user.utf8)) }
            return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.config.utf8))
        }
        StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let defaults = UserDefaults(suiteName: "notification-auth-" + UUID().uuidString)!
        let storage = NotificationAuthStorage()
        let state = AuthState(origin: try ServerOrigin("https://auth.example"), session: DeviceSession.make(configuration: configuration), settings: defaults, storage: storage)
        let restoring = Task { await state.restore() }
        for _ in 0..<500 { if gate.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        guard gate.entered else { gate.release(); await restoring.value; XCTFail("Identity request was not issued"); return }
        await state.invalidateSession(message: "Signed out.")
        gate.release(); await restoring.value
        XCTAssertEqual(state.stage, .signIn); XCTAssertNil(state.user); XCTAssertNil(state.selectedID); XCTAssertNil(state.notifications)
        let credentials = await state.service.refresh.current(); XCTAssertNil(credentials)
    }
}
private final class ForegroundIdentityCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
private final class IdentityResponseGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var released = false
    var entered: Bool { condition.lock(); defer { condition.unlock() }; return started }
    func wait() { condition.lock(); started = true; while !released { condition.wait() }; condition.unlock() }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
private final class NotificationAuthStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var pair: TokenPair? = TokenPair(access: "old", refresh: "old-refresh")
    func load() -> TokenPair? { lock.lock(); defer { lock.unlock() }; return pair }
    func store(_ value: TokenPair?) { lock.lock(); defer { lock.unlock() }; pair = value }
}
#endif
