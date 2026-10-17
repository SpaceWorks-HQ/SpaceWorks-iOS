#if DEBUG
import Foundation
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class AccountAuthTests: XCTestCase {
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func state(storage: AccountAuthStorage, me: @escaping () throws -> String) throws -> AuthState {
        StubProtocol.lock.lock(); StubProtocol.handler = { request in
            let data = request.url?.path == "/api/v1/auth/me" ? try me() : DebugAuthFixtures.config
            return (200, ["Content-Type": "application/json"], Data(data.utf8))
        }; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        return AuthState(origin: try ServerOrigin("https://account-auth-" + UUID().uuidString.lowercased() + ".example"),
            session: DeviceSession.make(configuration: configuration), settings: UserDefaults(suiteName: UUID().uuidString)!, storage: storage)
    }
    func testZeroMembershipIdentityKeepsGlobalSecurityAndDevicesWithoutMemberRecords() async throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DebugAuthFixtures.user.utf8)) as? [String: Any])
        object["makerspaces"] = []
        let identity = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let auth = try state(storage: AccountAuthStorage(), me: { identity }); await auth.restore()
        XCTAssertEqual(auth.stage, .signedIn); XCTAssertTrue(auth.memberships.isEmpty); XCTAssertNil(auth.selectedID)
        let global = try XCTUnwrap(auth.accountState(makerspaceID: nil))
        XCTAssertFalse(global.memberSelfServiceAvailable); XCTAssertFalse(global.dataExportAvailable); XCTAssertTrue(global.isActive)
        XCTAssertNil(auth.accountState(makerspaceID: 7, selfService: true, exports: true))
        await auth.invalidateSession(message: "Signed out.")
    }
    func testConfirmedLeaveClearsProtectedScopeBeforeOfflineRefetchAndRejectsStaleServerEcho() async throws {
        let response = AccountIdentityResponse(); let auth = try state(storage: AccountAuthStorage(), me: { try response.read() })
        await auth.restore(); await auth.select(7)
        var cleared = false; auth.registerPrivateHolder(UUID()) { cleared = true }
        response.offline = true
        await auth.confirmedMembershipLeave(7)
        XCTAssertTrue(cleared); XCTAssertNil(auth.selectedID); XCTAssertFalse(auth.memberships.contains { $0.id == 7 })
        XCTAssertEqual(Set(auth.memberships.map(\.id)), [8]); XCTAssertNotNil(auth.error)
        let selected = await auth.service.makerspace.current(); XCTAssertNil(selected)
        response.offline = false
        await auth.foreground()
        XCTAssertEqual(auth.selectedID, 8); XCTAssertFalse(auth.memberships.contains { $0.id == 7 }); XCTAssertFalse(auth.busy)
        await auth.invalidateSession(message: "Signed out.")
    }
    func testSecurityCodesArePresentedOnlyAfterTokenAndPrivateStateWipeThenExplicitlyCleared() async throws {
        let storage = AccountAuthStorage(); let auth = try state(storage: storage, me: { DebugAuthFixtures.user })
        await auth.restore(); await auth.select(7)
        var cleared = false; auth.registerPrivateHolder(UUID()) { cleared = true }
        await auth.securitySessionEnded(codes: ["demo-recovery-code"], message: "Save your new codes.")
        XCTAssertTrue(cleared); XCTAssertNil(storage.load()); XCTAssertNil(auth.user); XCTAssertNil(auth.selectedID)
        XCTAssertEqual(auth.stage, .securityCompletion); XCTAssertEqual(auth.recoveryCodes, ["demo-recovery-code"])
        XCTAssertEqual(auth.securityMessage, "Save your new codes.")
        auth.finishSecurityCompletion()
        XCTAssertEqual(auth.stage, .signIn); XCTAssertTrue(auth.recoveryCodes.isEmpty); XCTAssertNil(auth.securityMessage)
    }
}
private final class AccountIdentityResponse: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    var offline: Bool { get { lock.lock(); defer { lock.unlock() }; return value } set { lock.lock(); value = newValue; lock.unlock() } }
    func read() throws -> String { if offline { throw URLError(.notConnectedToInternet) }; return DebugAuthFixtures.user }
}
private final class AccountAuthStorage: TokenStorage, @unchecked Sendable {
    private let lock = NSLock(); private var pair: TokenPair? = .init(access: "account-auth", refresh: "account-refresh")
    func load() -> TokenPair? { lock.lock(); defer { lock.unlock() }; return pair }
    func store(_ value: TokenPair?) { lock.lock(); defer { lock.unlock() }; pair = value }
}
#endif
