import XCTest
import Security
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class PushRegistrationTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)
    func testExplicitConsentRegistersEachDirectMembershipAndDeduplicatesRestoredDigest() async throws {
        let repository = PushTestRepository(); let storage = PushMemoryStorage()
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.synchronize(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        let before = await repository.events; XCTAssertTrue(before.isEmpty)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        XCTAssertEqual(state.registeredMakerspaces, [7, 8])
        let saved = try storage.load()
        XCTAssertTrue(saved.enabled); XCTAssertEqual(saved.registrations.count, 2)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains(token))
        let restored = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await restored.load()
        await restored.synchronize(token: token.uppercased(), environment: "development", authorizedDirectMembershipIDs: [7, 8])
        let after = await repository.events
        XCTAssertEqual(after.map(\.kind), ["register", "register"])
    }
    func testRotationDeletesActualOldIDsBeforeRegisteringReplacementAndEnvironmentChangeDoesToo() async {
        let repository = PushTestRepository(); let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        await state.synchronize(token: String(repeating: "cd", count: 32), environment: "development", authorizedDirectMembershipIDs: [7])
        await state.synchronize(token: String(repeating: "cd", count: 32), environment: "production", authorizedDirectMembershipIDs: [7])
        let events = await repository.events
        XCTAssertEqual(events.map(\.kind), ["register", "delete", "register", "delete", "register"])
        XCTAssertEqual(events[1].deviceID, 701)
        XCTAssertEqual(events[3].deviceID, 702)
    }
    func testPermissionPausePreservesConsentAndSameStateCanSynchronizeAfterRestoration() async throws {
        let repository = PushTestRepository(); let storage = PushMemoryStorage()
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        await state.pause(authorizedDirectMembershipIDs: [7, 8])
        XCTAssertTrue(state.enabled); XCTAssertTrue(try storage.load().enabled)
        XCTAssertTrue(state.registeredMakerspaces.isEmpty); XCTAssertTrue(state.canRequest)
        await state.synchronize(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        let events = await repository.events
        XCTAssertEqual(events.map(\.kind), ["register", "register", "delete", "delete", "register", "register"])
        XCTAssertEqual(state.registeredMakerspaces, [7, 8])
    }
    func testPermissionPauseHonorsThrottleWithoutSendingCleanupRequests() async {
        let repository = PushTestRepository()
        let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true)
        await repository.failRegistration(status: 429, retryAfter: Date().addingTimeInterval(60))
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        await state.pause(authorizedDirectMembershipIDs: [7])
        let events = await repository.events
        XCTAssertEqual(events.map(\.kind), ["register"]); XCTAssertFalse(state.canRequest)
        state.invalidate()
    }
    func testMetadataFailureCannotHideCleanupThrottleOrAuthenticationRefusal() async throws {
        for status in [429, 401, 403] {
            let repository = PushTestRepository(); let storage = PushMemoryStorage()
            var unauthorized = 0; var forbidden = 0
            let state = PushRegistrationState(repository: repository, storage: storage, configured: true,
                onUnauthorized: { _ in unauthorized += 1 }, onForbidden: { forbidden += 1 })
            await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
            storage.failNonempty = true
            let deadline = Date().addingTimeInterval(60)
            await repository.failDeletion(status: status, retryAfter: status == 429 ? deadline : nil)
            await state.disable(authorizedDirectMembershipIDs: [7, 8])
            XCTAssertEqual(state.error, "Push cleanup refused.")
            XCTAssertEqual(unauthorized, status == 401 ? 1 : 0); XCTAssertEqual(forbidden, status == 403 ? 1 : 0)
            XCTAssertEqual(Set(try storage.load().registrations.map(\.makerspaceID)), [7, 8], "Failed persistence must retain server IDs")
            if status == 429 {
                XCTAssertEqual(state.retryAfter, deadline); XCTAssertFalse(state.canRequest)
                let before = await repository.events
                await state.disable(authorizedDirectMembershipIDs: [7, 8])
                await state.pause(authorizedDirectMembershipIDs: [7, 8])
                let removed = await state.removeMembership(7, authorizedDirectMembershipIDs: [7, 8])
                let after = await repository.events
                XCTAssertFalse(removed); XCTAssertEqual(before.count, after.count)
                XCTAssertEqual(before.filter { $0.kind == "delete" }.count, 1)
            }
            state.invalidate()
        }
    }
    func testCleanupThrottleBlocksRepeatedMutationsAndMembershipLeaveUntilConfirmed() async {
        let repository = PushTestRepository()
        let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        await repository.failDeletion(status: 429, retryAfter: Date().addingTimeInterval(60))
        let removed = await state.removeMembership(7, authorizedDirectMembershipIDs: [7, 8])
        XCTAssertFalse(removed); XCTAssertNotNil(state.error)
        let before = await repository.events
        await state.disable(authorizedDirectMembershipIDs: [7, 8])
        await state.resumeMembership(7, authorizedDirectMembershipIDs: [7, 8])
        XCTAssertGreaterThan(state.retryAfter, Date())
        let retry = await state.removeMembership(7, authorizedDirectMembershipIDs: [7, 8])
        let after = await repository.events
        XCTAssertFalse(retry); XCTAssertEqual(after.count, before.count)
        state.invalidate()
    }
    func testDemoAndUnconfiguredBuildNeverRegisterEvenWithPermissionOrCachedToken() async {
        let repository = PushTestRepository()
        for (configured, demo) in [(false, false), (true, true)] {
            let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: configured, isDemo: demo)
            await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
            await state.synchronize(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
            XCTAssertFalse(state.canRequest); XCTAssertTrue(state.registeredMakerspaces.isEmpty)
        }
        let events = await repository.events; XCTAssertTrue(events.isEmpty)
    }
    func testInvalidTokenOrEnvironmentCannotPersistConsentOrSendAnAPIRequest() async {
        let repository = PushTestRepository(); let storage = PushMemoryStorage()
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.enable(token: "bad-token", environment: "development", authorizedDirectMembershipIDs: [7])
        await state.enable(token: token, environment: "sandbox", authorizedDirectMembershipIDs: [7])
        let events = await repository.events; XCTAssertTrue(events.isEmpty)
        XCTAssertFalse((try? storage.load().enabled) ?? true)
    }
    func testStopWaitsForInFlightRegistrationAndBlocksLaterTokenCallbacksBeforeCleanup() async {
        let repository = PushTestRepository(); let gate = PushTestGate(); await repository.setGate(gate)
        let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true)
        let enabling = Task { await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7]) }
        await gate.waitUntilEntered()
        let stopping = Task { await state.stop(authorizedDirectMembershipIDs: [7]) }
        while state.canRequest { await Task.yield() }
        await state.synchronize(token: String(repeating: "ef", count: 32), environment: "development", authorizedDirectMembershipIDs: [7])
        await gate.release()
        await enabling.value; await stopping.value
        let events = await repository.events
        XCTAssertEqual(events.map(\.kind), ["register", "delete"])
        XCTAssertFalse(state.canRequest); XCTAssertTrue(state.registeredMakerspaces.isEmpty)
    }
    func testLeavingMembershipSuspendsQueuedRegistrationUntilFreshFailedLeaveIsResumed() async throws {
        let repository = PushTestRepository(); let coordinator = PushRegistrationCoordinator(repository: repository, storage: PushMemoryStorage())
        _ = try await coordinator.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        _ = try await coordinator.removeMembership(7, authorizedDirectMembershipIDs: [7, 8])
        _ = try await coordinator.reconcile(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        let suspended = await repository.events
        XCTAssertEqual(suspended.filter { $0.kind == "register" && $0.makerspaceID == 7 }.count, 1)
        _ = try await coordinator.resumeMembership(7, authorizedDirectMembershipIDs: [7, 8])
        _ = try await coordinator.reconcile(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        let resumed = await repository.events
        XCTAssertEqual(resumed.filter { $0.kind == "register" && $0.makerspaceID == 7 }.count, 2)
    }
    func testLostMembershipNeverSendsCleanupThroughAnUnauthorizedScope() async {
        let repository = PushTestRepository(); let storage = PushMemoryStorage()
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        await state.synchronize(token: token, environment: "development", authorizedDirectMembershipIDs: [8])
        XCTAssertEqual(state.registeredMakerspaces, [8])
        let events = await repository.events; XCTAssertEqual(events.count, 2)
        XCTAssertEqual(try? storage.load().registrations.map(\.makerspaceID), [8])
    }
    func testDisablePersistsConsentOffAndPendingFailedDeletesForNextAuthorizedRetry() async throws {
        let repository = PushTestRepository(); let storage = PushMemoryStorage()
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        await repository.failDeletes([7])
        await state.disable(authorizedDirectMembershipIDs: [7, 8])
        let saved = try storage.load()
        XCTAssertFalse(saved.enabled); XCTAssertEqual(saved.registrations.count, 1)
        XCTAssertTrue(saved.registrations[0].pendingDeletion)
        XCTAssertTrue(state.registeredMakerspaces.isEmpty)
        await repository.failDeletes([])
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
        XCTAssertEqual(state.registeredMakerspaces, [7, 8])
    }
    func testNewServerIDIsCleanedIfItsSecurePersistenceFails() async {
        let repository = PushTestRepository(); let storage = PushMemoryStorage(); storage.failNonempty = true
        let state = PushRegistrationState(repository: repository, storage: storage, configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        let events = await repository.events
        XCTAssertEqual(events.map(\.kind), ["register", "delete"])
        XCTAssertTrue(state.registeredMakerspaces.isEmpty); XCTAssertNotNil(state.error)
    }
    func testUnauthorizedCallbackCanAwaitStopWithoutReenteringHeldSerialLock() async {
        let repository = PushTestRepository(); await repository.failRegistration(status: 401)
        let box = PushStateBox()
        let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true,
            onUnauthorized: { _ in await box.stop() })
        box.state = state
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        XCTAssertFalse(state.canRequest); XCTAssertTrue(state.registeredMakerspaces.isEmpty)
    }
    func testThrottleKeepsRetryAfterAndPreventsAdditionalPermissionCallbackWrites() async {
        let repository = PushTestRepository(); let deadline = Date().addingTimeInterval(60)
        await repository.failRegistration(status: 429, retryAfter: deadline)
        let state = PushRegistrationState(repository: repository, storage: PushMemoryStorage(), configured: true)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        XCTAssertEqual(state.retryAfter, deadline)
        await state.enable(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        await state.synchronize(token: token, environment: "development", authorizedDirectMembershipIDs: [7])
        let events = await repository.events; XCTAssertEqual(events.count, 1)
        XCTAssertEqual(state.error, "Push refused.")
        state.invalidate()
    }
    func testKeychainMetadataIsDeviceOnlyAndIsolatedByAccountAndOrigin() throws {
        let origin = try ServerOrigin("https://push.example")
        let service = "org.spaceworks.tests.push." + UUID().uuidString
        let vault = PushRegistrationVault(origin: origin, accountID: 1, service: service)
        defer { try? vault.remove() }
        let record = PushStoredRegistration(makerspaceID: 7, deviceID: 701, tokenDigest: PushRegistrationVault.digest(token), environment: "development")
        let value = PushRegistrationSnapshot(enabled: true, registrations: [record])
        try vault.store(value); XCTAssertEqual(try vault.load(), value)
        XCTAssertTrue(try PushRegistrationVault(origin: origin, accountID: 2, service: service).load().registrations.isEmpty)
        XCTAssertTrue(try PushRegistrationVault(origin: ServerOrigin("https://other.example"), accountID: 1, service: service).load().registrations.isEmpty)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var attributes: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
        XCTAssertEqual((attributes as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}

@MainActor private final class PushStateBox: @unchecked Sendable {
    weak var state: PushRegistrationState?
    func stop() async { await state?.stop(authorizedDirectMembershipIDs: [7]) }
}

private final class PushMemoryStorage: PushRegistrationStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var saved = PushRegistrationSnapshot()
    var failNonempty = false
    func load() throws -> PushRegistrationSnapshot { lock.lock(); defer { lock.unlock() }; return saved }
    func store(_ snapshot: PushRegistrationSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        if failNonempty && !snapshot.registrations.isEmpty { throw APIError(status: 0, code: "storage_unavailable", detail: "Secure storage unavailable.") }
        saved = snapshot
    }
}

private actor PushTestGate {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func arrive() async { entered = true; observer?.resume(); observer = nil; await withCheckedContinuation { waiter = $0 } }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { observer = $0 } } }
    func release() { waiter?.resume(); waiter = nil }
}

private actor PushTestRepository: PushRegistrationRepository {
    struct Event: Sendable { let kind: String; let makerspaceID: Int; let deviceID: Int }
    private(set) var events: [Event] = []
    private var registerCounts: [Int: Int] = [:]
    private var registrationFailure: APIError?
    private var deletionFailure: APIError?
    private var failedDeletes = Set<Int>()
    private var gate: PushTestGate?
    func setGate(_ value: PushTestGate) { gate = value }
    func failDeletes(_ ids: Set<Int>) { failedDeletes = ids }
    func failRegistration(status: Int, retryAfter: Date? = nil) { registrationFailure = APIError(status: status, code: "push_refused", detail: "Push refused.", retryAfter: retryAfter) }
    func failDeletion(status: Int, retryAfter: Date? = nil) { deletionFailure = APIError(status: status, code: "push_cleanup_refused", detail: "Push cleanup refused.", retryAfter: retryAfter) }
    func register(makerspaceID: Int, token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> Components.Schemas.PushDevice {
        XCTAssertTrue(authorizedDirectMembershipIDs.contains(makerspaceID))
        registerCounts[makerspaceID, default: 0] += 1
        let id = makerspaceID * 100 + registerCounts[makerspaceID, default: 0]
        events.append(Event(kind: "register", makerspaceID: makerspaceID, deviceID: id))
        if let gate { self.gate = nil; await gate.arrive() }
        if let registrationFailure { throw registrationFailure }
        let json = """
        {"id":\(id),"provider":"apns","environment":"\(environment)","makerspace_id":\(makerspaceID),"active":true,"created_at":"2026-10-16T09:00:00Z","updated_at":"2026-10-16T09:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Components.Schemas.PushDevice.self, from: Data(json.utf8))
    }
    func unregister(makerspaceID: Int, deviceID: Int, authorizedDirectMembershipIDs: Set<Int>) async throws {
        XCTAssertTrue(authorizedDirectMembershipIDs.contains(makerspaceID))
        events.append(Event(kind: "delete", makerspaceID: makerspaceID, deviceID: deviceID))
        if let deletionFailure { throw deletionFailure }
        if failedDeletes.contains(makerspaceID) { throw APIError(status: 503, code: "offline", detail: "Offline.") }
    }
}
