import XCTest
import UserNotifications
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class NotificationSettingsTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)
    func testUnconfiguredAndDemoNeverAskPermissionOrRegister() async {
        for (configured, demo) in [(false, false), (true, true)] {
            let native = NotificationTestDevice(); let repository = NotificationTestRepository()
            let registration = PushRegistrationState(repository: repository, storage: NotificationTestStorage(), configured: configured, isDemo: demo)
            let state = NotificationSettingsState(registration: registration, native: native, environment: "development", memberships: { XCTFail("Unexpected identity request"); return [] })
            await state.prepare(); await state.enable(); await state.refresh(); await state.tokenChanged(token)
            XCTAssertEqual(native.requests, 0); XCTAssertEqual(native.refreshes, 0)
            let events = await repository.events; XCTAssertTrue(events.isEmpty)
        }
    }
    func testDeniedPermissionMakesNoServerRegistrationAndAllowsExplicitSettingsAction() async {
        let native = NotificationTestDevice(); native.authorization = .denied
        let repository = NotificationTestRepository(); var opened = false
        let state = NotificationSettingsState(registration: PushRegistrationState(repository: repository, storage: NotificationTestStorage(), configured: true), native: native, environment: "development", memberships: { XCTFail("Permission denied should not register"); return [] }, settings: { opened = true })
        await state.enable(); XCTAssertTrue(state.permissionDenied); state.openSettings(); XCTAssertTrue(opened)
        let events = await repository.events; XCTAssertTrue(events.isEmpty)
    }
    func testDelayedTokenUsesFreshMembershipsAndNeverRegistersBeforeExplicitEnable() async {
        let native = NotificationTestDevice(); native.authorization = .authorized
        let repository = NotificationTestRepository(); var lookups = 0
        let registration = PushRegistrationState(repository: repository, storage: NotificationTestStorage(), configured: true)
        let state = NotificationSettingsState(registration: registration, native: native, environment: "development", memberships: { lookups += 1; return [7, 8] })
        await state.prepare(); await state.tokenChanged(token); XCTAssertEqual(native.requests, 0); XCTAssertEqual(lookups, 0)
        await state.enable(); XCTAssertEqual(native.requests, 1); XCTAssertEqual(lookups, 0)
        native.token = token; await state.tokenChanged(token)
        XCTAssertEqual(lookups, 1); XCTAssertEqual(registration.registeredMakerspaces, [7, 8])
        await state.stop(authorizedDirectMembershipIDs: [7, 8]); await state.tokenChanged(token)
        let events = await repository.events; XCTAssertEqual(events, ["register-7", "register-8", "delete-7", "delete-8"])
    }
    func testIdentityRetryAfterBlocksRepeatedPermissionActionsAndTokenCallbacks() async {
        let native = NotificationTestDevice(); native.authorization = .authorized; native.token = token
        let repository = NotificationTestRepository(); var lookups = 0; let deadline = Date().addingTimeInterval(60)
        let state = NotificationSettingsState(registration: PushRegistrationState(repository: repository, storage: NotificationTestStorage(), configured: true), native: native, environment: "development", memberships: {
            lookups += 1; throw APIError(status: 429, code: "throttled", detail: "Wait before trying again.", retryAfter: deadline)
        })
        await state.enable(); await state.enable(); await state.tokenChanged(token); await state.refresh()
        XCTAssertEqual(lookups, 1); XCTAssertEqual(native.requests, 1); XCTAssertEqual(state.retryAfter, deadline)
        let events = await repository.events; XCTAssertTrue(events.isEmpty)
    }
    func testFreshIdentityFailureDoesNotTrustPreviousMembershipsOrPublishEnabledState() async {
        let native = NotificationTestDevice(); native.authorization = .authorized; native.token = token
        let repository = NotificationTestRepository()
        let registration = PushRegistrationState(repository: repository, storage: NotificationTestStorage(), configured: true)
        let state = NotificationSettingsState(registration: registration, native: native, environment: "development", memberships: { throw URLError(.notConnectedToInternet) })
        await state.enable(); XCTAssertEqual(state.error, "Couldn't connect. Try again."); XCTAssertFalse(registration.enabled)
        let events = await repository.events; XCTAssertTrue(events.isEmpty)
    }
}
@MainActor private final class NotificationTestDevice: NativePushAccess {
    var authorization = UNAuthorizationStatus.notDetermined
    var token: String?
    var error: String?
    var requests = 0
    var refreshes = 0
    func requestPermission() async { requests += 1 }
    func refreshAuthorization() async { refreshes += 1 }
}
private final class NotificationTestStorage: PushRegistrationStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = PushRegistrationSnapshot()
    func load() -> PushRegistrationSnapshot { lock.lock(); defer { lock.unlock() }; return snapshot }
    func store(_ value: PushRegistrationSnapshot) { lock.lock(); defer { lock.unlock() }; snapshot = value }
}
private actor NotificationTestRepository: PushRegistrationRepository {
    private(set) var events: [String] = []
    func register(makerspaceID: Int, token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) throws -> Components.Schemas.PushDevice {
        events.append("register-\(makerspaceID)")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Components.Schemas.PushDevice.self, from: Data("{\"id\":\(makerspaceID),\"provider\":\"apns\",\"environment\":\"\(environment)\",\"makerspace_id\":\(makerspaceID),\"active\":true,\"created_at\":\"2026-10-16T09:00:00Z\",\"updated_at\":\"2026-10-16T09:00:00Z\"}".utf8))
    }
    func unregister(makerspaceID: Int, deviceID: Int, authorizedDirectMembershipIDs: Set<Int>) { events.append("delete-\(makerspaceID)") }
}
