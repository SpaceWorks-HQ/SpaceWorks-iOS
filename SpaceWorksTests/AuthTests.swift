import XCTest
import Foundation
import SpaceWorksAPI
@testable import SpaceWorks

final class MemoryTokens: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var pair: TokenPair?
    var failWrites = false
    init(_ pair: TokenPair? = nil) { self.pair = pair }
    func load() throws -> TokenPair? { lock.lock(); defer { lock.unlock() }; return pair }
    func store(_ pair: TokenPair?) throws {
        lock.lock(); defer { lock.unlock() }
        if failWrites { throw APIError(status: 0, code: "storage", detail: "Secure storage unavailable.") }
        self.pair = pair
    }
}

@MainActor final class AuthTests: XCTestCase {
    private let json = ["Content-Type": "application/json"]
    private func state(storage: MemoryTokens = MemoryTokens(), handler: @escaping (URLRequest) throws -> (Int, String)) -> AuthState {
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            let (status, text) = try handler(request)
            return (status, self.json, Data(text.utf8))
        }
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        return AuthState(origin: try! ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: config),
            settings: UserDefaults(suiteName: UUID().uuidString)!, storage: storage,
            attest: { _ in Data(#"{"type":"development"}"#.utf8) })
    }
    private func response(_ request: URLRequest) throws -> (Int, String) {
        for header in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: header)) }
        switch request.url!.path {
        case "/api/v1/config": return (200, DebugAuthFixtures.config)
        case "/api/v1/auth/device/attestation-challenge":
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: String]
            XCTAssertEqual(body["platform"], "apple"); XCTAssertEqual(body["environment"], "development")
            return (200, #"{"challenge":"fresh-challenge","expires_in":120}"#)
        case "/api/v1/auth/device/login":
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["challenge"] as? String, "fresh-challenge")
            XCTAssertEqual((body["attestation"] as? [String: String])?["type"], "development")
            XCTAssertEqual(body["username"] as? String, "maker")
            return (200, DebugAuthFixtures.tokens)
        case "/api/v1/auth/me":
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
            return (200, DebugAuthFixtures.user)
        case "/api/v1/auth/device/logout": return (200, #"{"detail":"Signed out."}"#)
        default: XCTFail("Unexpected API call: \(request.url!)"); return (500, "{}")
        }
    }
    func testPasswordSignInPersistsBeforeIdentitySelectsAndLogsOut() async throws {
        let storage = MemoryTokens()
        let auth = state(storage: storage, handler: response)
        await auth.restore(); XCTAssertEqual(auth.stage, .signIn)
        auth.username = " maker "; auth.password = "password-fixture"
        await auth.signIn()
        XCTAssertEqual(auth.stage, .signedIn)
        XCTAssertEqual(try storage.load(), TokenPair(access: "test-access", refresh: "test-refresh"))
        XCTAssertEqual(auth.memberships.count, 2); XCTAssertNil(auth.selectedID)
        await auth.select(7); XCTAssertEqual(auth.selectedID, 7)
        XCTAssertEqual(auth.password, ""); XCTAssertFalse(auth.staffToolsAvailable)
        await auth.signOut(); XCTAssertNil(try storage.load()); XCTAssertNil(auth.user)
        XCTAssertEqual(auth.stage, .signIn)
    }
    func testMFARejectsAccessOnlyBrowserResult() async {
        let auth = state { request in
            if request.url!.path.hasSuffix("/login") { return (200, DebugAuthFixtures.mfa) }
            if request.url!.path.hasSuffix("/verify") { return (200, "{\"access\":\"web-access\",\"surface\":\"member\",\"user\":\(DebugAuthFixtures.user)}") }
            return try self.response(request)
        }
        await auth.restore(); auth.username = "maker"; auth.password = "password-fixture"; await auth.signIn()
        XCTAssertEqual(auth.stage, .mfa)
        auth.code = "123456"; await auth.verify()
        XCTAssertEqual(auth.stage, .mfa); XCTAssertNil(auth.user)
        XCTAssertEqual(auth.error, "This server did not provide a device session. Contact your makerspace.")
    }
    func testEnrollmentAndRecoveryCodesRequireConfirmation() async {
        let auth = state { request in
            switch request.url!.path {
            case "/api/v1/auth/device/login": return (200, DebugAuthFixtures.mfa.replacingOccurrences(of: "\"enrollment_required\":false", with: "\"enrollment_required\":true"))
            case "/api/v1/auth/mfa/enroll": return (200, DebugAuthFixtures.enrollment)
            case "/api/v1/auth/mfa/confirm": return (200, "{\"access\":\"test-access\",\"refresh\":\"test-refresh\",\"device_grant\":\(DebugAuthFixtures.grant),\"surface\":\"member\",\"user\":\(DebugAuthFixtures.user),\"recovery_codes\":[\"fixture-recovery\"]}")
            default: return try self.response(request)
            }
        }
        await auth.restore(); auth.username = "maker"; auth.password = "password-fixture"; await auth.signIn()
        XCTAssertNotNil(auth.enrollment); auth.code = "123456"; await auth.verify()
        XCTAssertEqual(auth.stage, .recoveryCodes); XCTAssertEqual(auth.recoveryCodes, ["fixture-recovery"])
        auth.confirmRecoveryCodes(); XCTAssertEqual(auth.stage, .signedIn); XCTAssertTrue(auth.recoveryCodes.isEmpty)
    }
    func testWrappedRevokedSessionOnForegroundClearsIdentity() async {
        let auth = state(storage: MemoryTokens(TokenPair(access: "test-access", refresh: "test-refresh"))) { request in
            if request.url!.path.hasSuffix("/refresh") { return (401, #"{"detail":"Session revoked.","code":"revoked"}"#) }
            return try self.response(request)
        }
        await auth.restore(); XCTAssertEqual(auth.stage, .signedIn)
        StubProtocol.lock.lock()
        StubProtocol.handler = { _ in (401, self.json, Data(#"{"detail":"Session revoked.","code":"revoked"}"#.utf8)) }
        StubProtocol.lock.unlock()
        await auth.foreground(); XCTAssertEqual(auth.stage, .signIn); XCTAssertNil(auth.user)
    }
    func testKeychainStoresWholePairScopedToServerAndRemovesIt() throws {
        let service = "org.spaceworks.tests.\(UUID().uuidString)"
        let vault = TokenVault(origin: try ServerOrigin("https://spaceworks.example"), service: service)
        let other = TokenVault(origin: try ServerOrigin("https://another.example"), service: service)
        defer { try? vault.store(nil) }
        try vault.store(TokenPair(access: "a1", refresh: "r1"))
        try vault.store(TokenPair(access: "a2", refresh: "r2"))
        XCTAssertEqual(try vault.load(), TokenPair(access: "a2", refresh: "r2")); XCTAssertNil(try other.load())
        try vault.store(nil); XCTAssertNil(try vault.load())
    }
    func testPersistenceFailurePreventsRefreshRetryAndClearsPair() async throws {
        let storage = MemoryTokens(TokenPair(access: "old", refresh: "old-refresh")); storage.failWrites = true
        let coordinator = RefreshCoordinator(pair: try storage.load(), persist: { try storage.store($0) }, rotate: { _ in TokenPair(access: "new", refresh: "new-refresh") })
        do { _ = try await coordinator.recover(rejectedAccess: "old"); XCTFail("Expected storage failure") } catch {}
        let current = await coordinator.current(); XCTAssertNil(current)
    }
    func testOfflineSignOutStillWipesLocalCredentials() async throws {
        let storage = MemoryTokens(TokenPair(access: "test-access", refresh: "test-refresh"))
        let auth = state(storage: storage) { request in
            if request.url!.path.hasSuffix("/logout") { throw URLError(.notConnectedToInternet) }
            return try self.response(request)
        }
        await auth.restore(); await auth.signOut()
        XCTAssertNil(try storage.load()); XCTAssertNil(auth.user); XCTAssertEqual(auth.stage, .signIn)
        XCTAssertEqual(auth.error, "Signed out on this device. Server revocation could not be confirmed.")
        let makerspace = await auth.service.makerspace.current(); XCTAssertNil(makerspace)
    }
    func testIsolatedDemoAuthRequiresCredentialsAndRecoveryAcknowledgement() {
        let demo = DemoSession(); demo.role = .staff; demo.scenario = .enrollment; demo.stage = .signIn
        demo.signIn(); XCTAssertEqual(demo.stage, .signIn); XCTAssertNotNil(demo.error)
        demo.username = "arjun"; demo.password = "sample"; demo.signIn(); XCTAssertEqual(demo.stage, .mfa)
        demo.code = "000000"; demo.verify(); XCTAssertEqual(demo.stage, .mfa)
        demo.code = "123456"; demo.verify(); XCTAssertEqual(demo.stage, .recovery)
        demo.reset(); XCTAssertEqual(demo.stage, .welcome); XCTAssertTrue(demo.password.isEmpty)
    }
}
