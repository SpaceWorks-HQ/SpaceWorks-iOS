#if DEBUG
import Foundation
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class EmailOwnerTests: XCTestCase {
    override func tearDown() { EmailOwnerProtocol.server = nil }

    private func make(_ server: EmailOwnerServer) throws -> AuthState {
        EmailOwnerProtocol.server = server
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [EmailOwnerProtocol.self]
        return AuthState(origin: try ServerOrigin("https://email-owner-" + UUID().uuidString.lowercased() + ".example"),
            session: DeviceSession.make(configuration: configuration), settings: UserDefaults(suiteName: UUID().uuidString)!,
            storage: MemoryTokens(.init(access: "old-access", refresh: "old-refresh")),
            attest: { _ in Data(#"{"type":"development"}"#.utf8) })
    }
    private func replace(_ auth: AuthState) async {
        await auth.invalidateSession(message: "Test replacement.")
        auth.username = "maker"; auth.password = "sample"
        await auth.signIn(); await auth.select(8)
        XCTAssertEqual(auth.stage, .signedIn); XCTAssertEqual(auth.selectedID, 8)
    }
    func testRetainedEmailFormCannotFirstSendUnderNewSameAccountInstallation() async throws {
        let server = EmailOwnerServer(); let auth = try make(server); await auth.restore(); await auth.select(7)
        let old = auth.accountForm(.emailVerification); old.code = "123456"
        await replace(auth)
        let baseline = server.requests.count
        await old.confirmEmail(); await old.resendEmail()
        XCTAssertEqual(server.requests.count, baseline); XCTAssertNil(old.notice)
        XCTAssertTrue(auth.accountForm(.emailVerification).canResend)
        XCTAssertEqual(auth.selectedID, 8); XCTAssertEqual(auth.stage, .signedIn)
        await auth.invalidateSession(message: "Test finished.")
    }
    func testDelayedEmailConfirmationCannotRefreshReplacementAccount() async throws {
        try await delayedAcknowledgement(confirm: true)
    }
    func testDelayedEmailResendCannotChangeReplacementCooldown() async throws {
        try await delayedAcknowledgement(confirm: false)
    }
    private func delayedAcknowledgement(confirm: Bool) async throws {
        let server = EmailOwnerServer(); server.holdPath = confirm ? EmailOwnerServer.confirm : EmailOwnerServer.resend
        defer { server.release() }
        let auth = try make(server); await auth.restore(); await auth.select(7)
        let old = auth.accountForm(.emailVerification); old.code = "123456"
        let request = Task { if confirm { await old.confirmEmail() } else { await old.resendEmail() } }
        for _ in 0..<500 { if server.hasHeldRequest { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        guard server.hasHeldRequest else { server.release(); await request.value; XCTFail("Email request never reached the server"); return }
        await replace(auth)
        let baseline = server.requests.count
        server.release(); await request.value
        XCTAssertEqual(server.requests.count, baseline, "An old acknowledgement must not issue a new-owner /me")
        XCTAssertNil(old.notice); XCTAssertTrue(auth.accountForm(.emailVerification).canResend)
        XCTAssertEqual(auth.stage, .signedIn); XCTAssertEqual(auth.selectedID, 8)
        let pair = await auth.service.refresh.current(); XCTAssertEqual(pair?.access, "new-access")
        await auth.invalidateSession(message: "Test finished.")
    }
    func testEmailOwnerSurvivesTokenRotationWithoutMakerspaceHeader() async throws {
        let server = EmailOwnerServer(); server.rejectOldEmail = true
        let auth = try make(server); await auth.restore(); await auth.select(7)
        let form = auth.accountForm(.emailVerification); form.code = "123456"
        await form.confirmEmail()
        XCTAssertEqual(form.notice, "Email confirmed."); XCTAssertNil(form.error)
        await form.resendEmail(); XCTAssertNil(form.error); XCTAssertFalse(form.canResend)
        let calls = server.requests
        XCTAssertEqual(calls.filter { $0.path == "/api/v1/auth/device/refresh" }.count, 1)
        let email = calls.filter { $0.path == EmailOwnerServer.confirm || $0.path == EmailOwnerServer.resend }
        XCTAssertEqual(email.count, 3); XCTAssertTrue(email.allSatisfy { $0.makerspace == nil })
        XCTAssertEqual(email.map(\.authorization), ["Bearer old-access", "Bearer rotated-access", "Bearer rotated-access"])
        XCTAssertEqual(auth.stage, .signedIn); XCTAssertEqual(auth.selectedID, 7)
        await auth.invalidateSession(message: "Test finished.")
    }
    func testRefusedRefreshClearsCurrentEmailOwnerAndPrivateState() async throws {
        for confirm in [true, false] {
            let server = EmailOwnerServer(); server.rejectOldEmail = true; server.rejectRefresh = true
            let auth = try make(server); await auth.restore(); await auth.select(7)
            var cleared = false; auth.registerPrivateHolder(UUID()) { cleared = true }
            let form = auth.accountForm(.emailVerification); form.code = "123456"
            if confirm { await form.confirmEmail() } else { await form.resendEmail() }
            XCTAssertTrue(cleared); XCTAssertEqual(auth.stage, .signIn); XCTAssertNil(auth.user); XCTAssertNil(auth.selectedID)
            let pair = await auth.service.refresh.current(); XCTAssertNil(pair)
            XCTAssertEqual(auth.error, "Session revoked."); XCTAssertNil(form.notice)
            XCTAssertEqual(server.requests.filter { $0.path == "/api/v1/auth/device/refresh" }.count, 1)
        }
    }
    func testValidationThrottleAndOfflineErrorsKeepVerifiedEmailOwner() async throws {
        for failure in [EmailOwnerServer.Failure.validation, .throttle, .offline] {
            let server = EmailOwnerServer(); server.emailFailure = failure
            let auth = try make(server); await auth.restore(); await auth.select(7)
            var cleared = false; auth.registerPrivateHolder(UUID()) { cleared = true }
            let form = auth.accountForm(.emailVerification); form.code = "123456"
            await form.confirmEmail()
            XCTAssertFalse(cleared); XCTAssertEqual(auth.stage, .signedIn); XCTAssertNotNil(auth.user); XCTAssertEqual(auth.selectedID, 7)
            XCTAssertNotNil(form.error); XCTAssertNil(form.notice)
            let pair = await auth.service.refresh.current(); XCTAssertEqual(pair?.access, "old-access")
            if failure == .throttle { XCTAssertFalse(form.canResend) }
            XCTAssertFalse(server.requests.contains { $0.path == "/api/v1/auth/device/refresh" })
            await auth.invalidateSession(message: "Test finished.")
        }
    }
}

private final class EmailOwnerServer: @unchecked Sendable {
    static let confirm = "/api/v1/auth/email-verification/confirm"
    static let resend = "/api/v1/auth/email-verification/resend"
    struct Request { let path: String; let authorization: String?; let makerspace: String? }
    enum Failure: Equatable { case validation, throttle, offline }
    private let lock = NSLock()
    private var records: [Request] = []
    private var held: EmailOwnerProtocol?
    private var heldPath: String?
    private var rejectsOldEmail = false
    private var rejectsRefresh = false
    private var failure: Failure?
    var holdPath: String? {
        get { lock.lock(); defer { lock.unlock() }; return heldPath }
        set { lock.lock(); heldPath = newValue; lock.unlock() }
    }
    var rejectOldEmail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return rejectsOldEmail }
        set { lock.lock(); rejectsOldEmail = newValue; lock.unlock() }
    }
    var rejectRefresh: Bool {
        get { lock.lock(); defer { lock.unlock() }; return rejectsRefresh }
        set { lock.lock(); rejectsRefresh = newValue; lock.unlock() }
    }
    var emailFailure: Failure? {
        get { lock.lock(); defer { lock.unlock() }; return failure }
        set { lock.lock(); failure = newValue; lock.unlock() }
    }
    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return records }
    var hasHeldRequest: Bool { lock.lock(); defer { lock.unlock() }; return held != nil }
    func handle(_ source: EmailOwnerProtocol) {
        let request = source.request; let path = request.url!.path
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        lock.lock()
        records.append(.init(path: path, authorization: authorization, makerspace: request.value(forHTTPHeaderField: "X-Makerspace-Id")))
        if path == heldPath { held = source; lock.unlock(); return }
        let reject = rejectsOldEmail
        let refuseRefresh = rejectsRefresh
        let emailFailure = failure
        lock.unlock()
        if [Self.confirm, Self.resend].contains(path), let emailFailure {
            switch emailFailure {
            case .validation: source.respond(status: 400, json: #"{"detail":"Invalid verification code."}"#)
            case .throttle: source.respond(status: 429, json: #"{"detail":"Try again later."}"#, headers: ["Retry-After": "120"])
            case .offline: source.client?.urlProtocol(source, didFailWithError: URLError(.notConnectedToInternet))
            }
            return
        }
        if reject, [Self.confirm, Self.resend].contains(path), authorization == "Bearer old-access" {
            source.respond(status: 401, json: #"{"detail":"Expired."}"#); return
        }
        if refuseRefresh, path == "/api/v1/auth/device/refresh" {
            source.respond(status: 401, json: #"{"detail":"Session revoked."}"#); return
        }
        let body: String
        switch path {
        case "/api/v1/config": body = DebugAuthFixtures.config
        case "/api/v1/auth/me": body = DebugAuthFixtures.user
        case "/api/v1/auth/device/attestation-challenge": body = #"{"challenge":"fixture-challenge","expires_in":120}"#
        case "/api/v1/auth/device/login": body = DebugAuthFixtures.tokens.replacingOccurrences(of: "test-access", with: "new-access").replacingOccurrences(of: "test-refresh", with: "new-refresh")
        case "/api/v1/auth/device/refresh": body = DeviceRefreshFixture.rotated
        case Self.confirm, Self.resend: body = #"{"detail":"Accepted."}"#
        default: XCTFail("Unexpected email-owner API call: " + path); source.respond(status: 500, json: "{}"); return
        }
        source.respond(status: 200, json: body)
    }
    func release() {
        lock.lock(); let source = held; held = nil; heldPath = nil; lock.unlock()
        source?.respond(status: 200, json: #"{"detail":"Accepted."}"#)
    }
}
private final class EmailOwnerProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var currentServer: EmailOwnerServer?
    static var server: EmailOwnerServer? {
        get { lock.lock(); defer { lock.unlock() }; return currentServer }
        set { lock.lock(); currentServer = newValue; lock.unlock() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.server?.handle(self) }
    override func stopLoading() {}
    func respond(status: Int, json: String, headers: [String: String] = [:]) {
        var fields = headers; fields["Content-Type"] = "application/json"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: fields)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
