import XCTest
import Foundation
import SpaceWorksAPI
@testable import SpaceWorks

private final class SeenPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    private var bodies: [String: [String: Any]] = [:]
    func record(_ request: URLRequest) {
        let body = (try? JSONSerialization.jsonObject(with: requestBody(request))) as? [String: Any]
        lock.lock(); values.append(request.url!.path); if let body { bodies[request.url!.path] = body }; lock.unlock()
    }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func body(_ path: String) -> [String: Any]? { lock.lock(); defer { lock.unlock() }; return bodies[path] }
}

@MainActor final class NativeAuthTests: XCTestCase {
    private let json = ["Content-Type": "application/json"]
    static func config(minimum: String? = nil, password: Bool = true, phone: Bool = false, google: String? = nil,
                       apple: Bool = false, oidc: String = "") -> String {
        let min = minimum.map { "\"\($0)\"" } ?? "null"
        let googleValue = google.map { #"{"android_client_id":"","ios_client_id":"\#($0)"}"# } ?? "null"
        let appleValue = apple ? #"{"enabled":true}"# : "null"
        return #"{"email_enabled":false,"public_image_max_bytes":10485760,"password_login":{"member":true},"native":{"min_app_version":{"android":null,"ios":\#(min)},"providers":{"password":\#(password),"phone":\#(phone),"google":\#(googleValue),"apple":\#(appleValue),"oidc":[\#(oidc)]}}}"#
    }
    private func state(storage: MemoryTokens = MemoryTokens(), version: String = "1.4.0", seen: SeenPaths = SeenPaths(),
                       handler: @escaping (URLRequest) throws -> (Int, String)) -> AuthState {
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            for header in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: header)) }
            seen.record(request)
            let (status, text) = try handler(request)
            return (status, self.json, Data(text.utf8))
        }
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        return AuthState(origin: try! ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: config),
            settings: UserDefaults(suiteName: UUID().uuidString)!, storage: storage, appVersion: version,
            attest: { _ in Data(#"{"type":"development"}"#.utf8) })
    }
    private func common(_ request: URLRequest, config: String = NativeAuthTests.config(), user: String = DebugAuthFixtures.user) -> (Int, String)? {
        switch request.url!.path {
        case "/api/v1/config": return (200, config)
        case "/api/v1/auth/device/attestation-challenge": return (200, #"{"challenge":"fresh-challenge","expires_in":120}"#)
        case "/api/v1/auth/me": return (200, user)
        default: return nil
        }
    }

    func testVersionGateComparesDottedNumbersAndIgnoresMalformedMinimums() {
        XCTAssertFalse(AppVersion.isBelow("1.10.0", minimum: "1.9"))
        XCTAssertTrue(AppVersion.isBelow("1.9", minimum: "1.10"))
        XCTAssertFalse(AppVersion.isBelow("1.4", minimum: "1.4.0"))
        XCTAssertTrue(AppVersion.isBelow("1.4.0", minimum: "1.4.1"))
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: nil))
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "2.0-beta"), "A malformed server minimum never blocks")
        XCTAssertTrue(AppVersion.isBelow("", minimum: "1.0"), "An unreadable app version is treated as outdated")
    }

    func testMinimumVersionGateStopsBeforeIdentityAndKeepsStoredCredentials() async throws {
        let storage = MemoryTokens(TokenPair(access: "test-access", refresh: "test-refresh"))
        let seen = SeenPaths()
        var minimum = "2.0.0"
        let auth = state(storage: storage, seen: seen) { request in
            if let value = self.common(request, config: NativeAuthTests.config(minimum: minimum)) { return value }
            XCTFail("Unexpected API call: \(request.url!)"); return (500, "{}")
        }
        await auth.restore()
        XCTAssertEqual(auth.stage, .updateRequired); XCTAssertEqual(auth.minimumVersion, "2.0.0")
        XCTAssertFalse(seen.paths.contains("/api/v1/auth/me"), "No identity request below the published minimum")
        XCTAssertEqual(try storage.load(), TokenPair(access: "test-access", refresh: "test-refresh"))
        minimum = "1.4"
        await auth.retryRestore()
        XCTAssertEqual(auth.stage, .signedIn)
    }

    func testOnlyPublishedNativeProvidersAreOffered() async {
        let organization = #"{"key":"oidc:campus","display_name":"Campus SSO","client_id":"campus-app","issuer":"https://id.example.test"},{"key":"github","display_name":"Ignored","client_id":"x","issuer":"https://x.example"}"#
        let auth = state { request in
            self.common(request, config: NativeAuthTests.config(password: false, phone: true, google: "1234.apps.googleusercontent.com", apple: true, oidc: organization)) ?? (500, "{}")
        }
        await auth.restore()
        XCTAssertFalse(auth.passwordEnabled); XCTAssertTrue(auth.phoneEnabled); XCTAssertTrue(auth.appleEnabled)
        XCTAssertEqual(auth.googleClientID, "1234.apps.googleusercontent.com")
        XCTAssertEqual(auth.organizationProviders.map(\.key), ["oidc:campus"], "Only valid configured OIDC keys render")
        let legacy = state { request in self.common(request, config: DebugAuthFixtures.config) ?? (500, "{}") }
        await legacy.restore()
        XCTAssertTrue(legacy.passwordEnabled); XCTAssertFalse(legacy.hasProviders, "A server without native config offers no native providers")
    }

    func testSocialSignInBindsNonceChallengeAndAttestationThenInstallsTheDeviceGrant() async throws {
        let storage = MemoryTokens(); let seen = SeenPaths()
        let auth = state(storage: storage, seen: seen) { request in
            if let value = self.common(request) { return value }
            switch request.url!.path {
            case "/api/v1/auth/social/nonce": return (200, #"{"nonce":"server-nonce","expires_in":300}"#)
            case "/api/v1/auth/social/oidc/campus":
                return (200, "{\"access\":\"social-access\",\"refresh\":\"social-refresh\",\"device_grant\":\(DebugAuthFixtures.grant),\"user\":{},\"outcome\":\"login\"}")
            default: XCTFail("Unexpected API call: \(request.url!)"); return (500, "{}")
            }
        }
        await auth.restore()
        var issuedNonce: String?
        await auth.signIn(with: .oidc(slug: "campus")) { nonce in issuedNonce = nonce; return ProviderCredential(idToken: "provider-id-token") }
        XCTAssertEqual(issuedNonce, "server-nonce")
        let nonce = try XCTUnwrap(seen.body("/api/v1/auth/social/nonce"))
        XCTAssertEqual(nonce["provider"] as? String, "oidc:campus"); XCTAssertEqual(nonce["delivery"] as? String, "device")
        XCTAssertEqual(nonce["client_platform"] as? String, "ios"); XCTAssertEqual(nonce["challenge"] as? String, "fresh-challenge")
        XCTAssertEqual(nonce["surface"] as? String, "member")
        let login = try XCTUnwrap(seen.body("/api/v1/auth/social/oidc/campus"))
        XCTAssertEqual(login["id_token"] as? String, "provider-id-token"); XCTAssertEqual(login["nonce"] as? String, "server-nonce")
        XCTAssertEqual((login["attestation"] as? [String: Any])?["type"] as? String, "development")
        XCTAssertEqual(auth.stage, .signedIn)
        XCTAssertEqual(try storage.load(), TokenPair(access: "social-access", refresh: "social-refresh"))
    }

    func testSocialResultWithoutDeviceGrantNeverOpensASession() async throws {
        let storage = MemoryTokens()
        let auth = state(storage: storage) { request in
            if let value = self.common(request) { return value }
            if request.url!.path == "/api/v1/auth/social/nonce" { return (200, #"{"nonce":"server-nonce","expires_in":300}"#) }
            return (200, #"{"access":"web-access","user":{},"outcome":"login"}"#)
        }
        await auth.restore()
        await auth.signIn(with: .google) { _ in ProviderCredential(idToken: "provider-id-token") }
        XCTAssertEqual(auth.stage, .signIn); XCTAssertNil(try storage.load())
        XCTAssertEqual(auth.error, "This server did not provide a device session. Contact your makerspace.")
    }

    func testCancelledProviderLeavesSignInQuiet() async {
        let auth = state { request in
            if let value = self.common(request) { return value }
            return (200, #"{"nonce":"server-nonce","expires_in":300}"#)
        }
        await auth.restore()
        await auth.signIn(with: .apple) { _ in throw CancellationError() }
        XCTAssertEqual(auth.stage, .signIn); XCTAssertNil(auth.error); XCTAssertNil(auth.feedback)
    }

    func testSuperadminRefusalShowsTheWebConsoleNotice() async {
        let auth = state { request in
            if let value = self.common(request) { return value }
            return (403, #"{"detail":"Superadmin accounts must use the web console.","code":"device_superadmin_not_supported"}"#)
        }
        await auth.restore(); auth.username = "root"; auth.password = "password-fixture"
        await auth.signIn()
        XCTAssertEqual(auth.stage, .webConsole); XCTAssertNil(auth.user); XCTAssertEqual(auth.password, "")
        auth.leaveWebConsoleNotice()
        XCTAssertEqual(auth.stage, .signIn)
    }

    func testPhoneSignInBindsItsChallengeToTheCodeAndContinuesToMFA() async throws {
        let seen = SeenPaths()
        let auth = state(seen: seen) { request in
            if let value = self.common(request, config: NativeAuthTests.config(phone: true)) { return value }
            switch request.url!.path {
            case "/api/v1/auth/phone/login/start": return (200, #"{"detail":"If the number can sign in, a code was sent."}"#)
            case "/api/v1/auth/phone/login/confirm": return (200, DebugAuthFixtures.mfa)
            default: XCTFail("Unexpected API call: \(request.url!)"); return (500, "{}")
            }
        }
        await auth.restore()
        let phone = auth.phoneSignIn()
        phone.number = "98765 43210"; await phone.send()
        XCTAssertEqual(phone.error, "Enter your phone number with its country code."); XCTAssertEqual(phone.step, .number)
        phone.number = "+91 98765-43210"; await phone.send()
        XCTAssertEqual(phone.step, .code); XCTAssertEqual(phone.phone, "+919876543210")
        let start = try XCTUnwrap(seen.body("/api/v1/auth/phone/login/start"))
        XCTAssertEqual(start["delivery"] as? String, "device"); XCTAssertEqual(start["client_platform"] as? String, "ios")
        XCTAssertEqual(start["challenge"] as? String, "fresh-challenge"); XCTAssertNil(start["code"])
        phone.code = "12345"; await phone.verify(); XCTAssertEqual(phone.error, "Enter the six-digit code.")
        phone.code = "123456"; await phone.verify()
        let confirm = try XCTUnwrap(seen.body("/api/v1/auth/phone/login/confirm"))
        XCTAssertEqual(confirm["phone"] as? String, "+919876543210"); XCTAssertEqual(confirm["code"] as? String, "123456")
        XCTAssertEqual(confirm["challenge"] as? String, "fresh-challenge")
        XCTAssertEqual((confirm["attestation"] as? [String: Any])?["type"] as? String, "development")
        XCTAssertEqual(auth.stage, .mfa)
    }

    func testExpiredPhoneChallengeRequiresANewCodeWithoutContactingTheServer() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        var confirms = 0
        let phone = PhoneSignInState(begin: { _ in .init(challenge: "bound", expires: clock.addingTimeInterval(180)) },
                                     finish: { _, _, _ in confirms += 1 }, now: { clock })
        phone.number = "+15551234567"; await phone.send()
        XCTAssertEqual(phone.step, .code)
        clock = clock.addingTimeInterval(181)
        phone.code = "123456"; await phone.verify()
        XCTAssertEqual(confirms, 0)
        XCTAssertEqual(phone.error, "Your code expired. Send a new code.")
        XCTAssertLessThanOrEqual(phone.resendAfter, clock, "A new code can be requested immediately")
    }

    func testStaffToolsRequireANativeStaffSessionAuthority() async {
        for (authority, expected) in [("member", false), ("native_staff", true), ("staff", false)] {
            let auth = state(storage: MemoryTokens(TokenPair(access: "test-access", refresh: "test-refresh"))) { request in
                self.common(request, user: DebugAuthFixtures.user(memberships: [DebugAuthFixtures.membership], authority: authority)) ?? (500, "{}")
            }
            await auth.restore()
            XCTAssertEqual(auth.stage, .signedIn)
            XCTAssertEqual(auth.staffToolsAvailable, expected, authority)
        }
    }

    func testSignOutEverywhereClearsThisDeviceOnlyAfterTheServerConfirms() async throws {
        var available = false
        let storage = MemoryTokens(TokenPair(access: "test-access", refresh: "test-refresh"))
        let auth = state(storage: storage) { request in
            if let value = self.common(request) { return value }
            XCTAssertEqual(request.url!.path, "/api/v1/auth/logout-all"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            return available ? (200, #"{"web_sessions":2,"devices":3}"#) : (503, #"{"detail":"Try again later.","code":"unavailable"}"#)
        }
        await auth.restore(); XCTAssertEqual(auth.stage, .signedIn)
        await auth.signOutEverywhere()
        XCTAssertEqual(auth.stage, .signedIn, "A failed request keeps the session"); XCTAssertNotNil(try storage.load())
        XCTAssertEqual(auth.error, "Try again later.")
        available = true
        await auth.signOutEverywhere()
        XCTAssertEqual(auth.stage, .signIn); XCTAssertNil(auth.user); XCTAssertNil(try storage.load())
        XCTAssertEqual(auth.error, "Signed out on every device and browser.")
    }

    func testAppAttestProofKeepsItsAppleTypeInTheOpenVerifierAlternative() throws {
        let proof = Data(#"{"type":"app_attest","key_id":"a2V5","attestation":"Y2Jvcg=="}"#.utf8)
        let payload = try DeviceAttestation.payload(proof)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String]
        XCTAssertEqual(encoded, ["type": "app_attest", "key_id": "a2V5", "attestation": "Y2Jvcg=="])
    }
}
