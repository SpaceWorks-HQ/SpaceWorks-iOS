import XCTest
import Foundation
import SpaceWorksAPI
@testable import SpaceWorks

private actor DeletionFake: AccountDeletionRepository {
    var blockers: [String] = []
    var methods = ["password", "totp", "phone", "google", "github", "oidc:campus"]
    var verified = false
    var mfa = true
    var deleteFailure: APIError?
    var reauthCalls: [(String, String?)] = []
    var deleted = 0
    func configure(blockers: [String]) { self.blockers = blockers }
    func configure(deleteFailure: APIError?) { self.deleteFailure = deleteFailure }
    func configure(verified: Bool) { self.verified = verified }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
    private func blocker(_ code: String) -> String {
        #"{"code":"\#(code)","makerspace_id":7,"makerspace_slug":"fab-lab","makerspace_member_url":null,"organization_url":null,"organization_id":null,"count":2,"detail":"Server detail for \#(code)."}"#
    }
    func preview() async throws -> Components.Schemas.AccountDeletionPreview {
        let rows = blockers.map(blocker).joined(separator: ",")
        let names = methods.map { "\"\($0)\"" }.joined(separator: ",")
        return try decode(#"{"deletable":\#(blockers.isEmpty),"restorable":true,"restore_reason":"","blockers":[\#(rows)],"reauth":{"required":true,"methods":[\#(names)]}}"#)
    }
    func status() async throws -> Components.Schemas.ReauthenticationStatus {
        try decode(#"{"verified":\#(verified),"password_available":true,"mfa_enabled":\#(mfa),"providers":["google"]}"#)
    }
    func reauthenticate(password: String, code: String?) async throws -> Components.Schemas.ReauthenticationResult {
        reauthCalls.append((password, code))
        guard password == "correct-password", code == "123456" else {
            throw APIError(status: 0, code: "identity_verification_failed", detail: "Identity verification failed.")
        }
        return try decode(#"{"verified":true,"expires_in":600}"#)
    }
    func startPhone() async throws -> Components.Schemas.ReauthenticationPhoneStarted { try decode(#"{"sent":true,"token":"phone-token"}"#) }
    func confirmPhone(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        XCTAssertEqual(token, "phone-token"); return try decode(#"{"verified":true,"expires_in":600}"#)
    }
    func startSocial(provider: String) async throws -> Components.Schemas.ReauthenticationSocialStarted {
        try decode(#"{"authorization_url":"https://accounts.example/auth","state":"server-state","nonce":"server-nonce","expires_in":300}"#)
    }
    func completeSocial(state: String, nonce: String, idToken: String) async throws -> Components.Schemas.ReauthenticationResult {
        XCTAssertEqual(state, "server-state"); XCTAssertEqual(nonce, "server-nonce"); XCTAssertEqual(idToken, "provider-token")
        return try decode(#"{"verified":false,"expires_in":0,"mfa_required":true,"factor_required":"totp","factor_token":"factor-token"}"#)
    }
    func factor(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        XCTAssertEqual(token, "factor-token"); return try decode(#"{"verified":true,"expires_in":600}"#)
    }
    func delete() async throws -> Components.Schemas.AccountDeletionResult {
        if let deleteFailure { self.deleteFailure = nil; throw deleteFailure }
        deleted += 1
        return try decode(#"{"deleted_at":"2026-10-18T10:00:00Z","purge_after":"2027-01-16T10:00:00Z"}"#)
    }
}

@MainActor final class AccountDeletionTests: XCTestCase {
    func testBlockersAreShownWithServerDetailAndInAppFixDestinations() async {
        let fake = DeletionFake(); await fake.configure(blockers: ["unpaid_charges", "active_loans", "last_manager", "future_code"])
        let state = AccountDeletionState(repository: fake, onDeleted: { _, _ in XCTFail("Blocked accounts are never deleted") })
        await state.load()
        XCTAssertEqual(state.stage, .blockers)
        XCTAssertEqual(state.blockers.map(\.detail).last, "Server detail for future_code.", "Unknown codes keep their server detail")
        XCTAssertEqual(state.blockers.map { AccountDeletionState.destination(for: $0) }, [.payments, .activity, nil, nil])
    }

    func testOnlyNativelyCompletableMethodsAreOffered() async {
        let state = AccountDeletionState(repository: DeletionFake(), onDeleted: { _, _ in })
        await state.load()
        XCTAssertEqual(state.methods, [.password, .phone, .social("google"), .social("oidc:campus")], "TOTP pairs with the password and GitHub is web-only")
        XCTAssertTrue(state.authenticatorRequired)
    }

    func testPasswordProofThenTypedConfirmationDeletesOnce() async {
        let fake = DeletionFake()
        var deletedRestorable: Bool?
        let state = AccountDeletionState(repository: fake, onDeleted: { _, restorable in deletedRestorable = restorable })
        await state.load(); XCTAssertEqual(state.stage, .verify)
        state.password = "wrong"; state.code = "123456"; await state.verifyPassword()
        XCTAssertEqual(state.stage, .verify); XCTAssertEqual(state.error, "Identity verification failed.")
        state.password = "correct-password"; state.code = "12"; await state.verifyPassword()
        XCTAssertEqual(state.error, "Enter the six-digit code from your authenticator app.")
        state.code = "123456"; await state.verifyPassword()
        XCTAssertEqual(state.stage, .confirm); XCTAssertEqual(state.password, "", "Secrets are cleared after proof")
        state.confirmation = "delete"; XCTAssertFalse(state.canDelete)
        state.confirmation = "DELETE"; XCTAssertTrue(state.canDelete)
        await state.delete()
        XCTAssertEqual(state.stage, .deleted); XCTAssertEqual(deletedRestorable, true)
        let deleted = await fake.deleted
        XCTAssertEqual(deleted, 1)
    }

    func testExpiredProofReturnsToVerificationWithoutDeleting() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let fake = DeletionFake()
        let state = AccountDeletionState(repository: fake, onDeleted: { _, _ in XCTFail("An expired proof must not delete") }, now: { clock })
        await state.load()
        state.password = "correct-password"; state.code = "123456"; await state.verifyPassword()
        XCTAssertEqual(state.stage, .confirm)
        clock = clock.addingTimeInterval(601)
        state.confirmation = "DELETE"; await state.delete()
        XCTAssertEqual(state.stage, .verify); XCTAssertEqual(state.error, "Verify your identity again before deleting.")
        let deleted = await fake.deleted
        XCTAssertEqual(deleted, 0)
    }

    func testConflictAtConfirmationRefetchesTheAuthoritativeBlockers() async {
        let fake = DeletionFake()
        let state = AccountDeletionState(repository: fake, onDeleted: { _, _ in XCTFail("A conflict must not delete") })
        await state.load(); state.password = "correct-password"; state.code = "123456"; await state.verifyPassword()
        await fake.configure(blockers: ["upcoming_bookings"])
        await fake.configure(deleteFailure: APIError(status: 409, code: "http_409", detail: "This changed. Refresh and try again."))
        state.confirmation = "DELETE"; await state.delete()
        XCTAssertEqual(state.stage, .blockers); XCTAssertEqual(state.blockers.first?.code, "upcoming_bookings")
        XCTAssertEqual(state.notice, "Something changed. Review the updated list before continuing.")
    }

    func testSocialProofCanRequireASecondFactor() async {
        let state = AccountDeletionState(repository: DeletionFake(), socialCredential: { provider, nonce in
            XCTAssertEqual(provider, "google"); XCTAssertEqual(nonce, "server-nonce")
            return ProviderCredential(idToken: "provider-token")
        }, onDeleted: { _, _ in })
        await state.load()
        await state.verifySocial("google")
        XCTAssertEqual(state.stage, .factor); XCTAssertEqual(state.factorKind, .totp)
        state.code = "654321"; await state.verifyFactor()
        XCTAssertEqual(state.stage, .confirm)
    }

    func testPhoneOnlyProofUsesTheSeparateReauthenticationCode() async {
        let state = AccountDeletionState(repository: DeletionFake(), onDeleted: { _, _ in })
        await state.load(); state.method = .phone
        await state.sendPhoneCode()
        XCTAssertEqual(state.phoneToken, "phone-token"); XCTAssertEqual(state.notice, "We sent a verification code to your phone.")
        state.code = "111222"; await state.verifyPhone()
        XCTAssertEqual(state.stage, .confirm)
    }

    func testWebFixesOpenOnlyOnTheConnectedDeploymentOrigin() throws {
        let origin = try ServerOrigin("https://spaceworks.example")
        XCTAssertNotNil(AccountDeletionState.trustedWebFix("https://spaceworks.example/organizations/4", origin: origin))
        XCTAssertNil(AccountDeletionState.trustedWebFix("https://evil.example/organizations/4", origin: origin))
        XCTAssertNil(AccountDeletionState.trustedWebFix("http://spaceworks.example/organizations/4", origin: origin))
        XCTAssertNil(AccountDeletionState.trustedWebFix(nil, origin: origin))
    }

    func testGeneratedDeletionOperationsUseTheDocumentedGlobalRequests() async throws {
        var seen: [String] = []
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            seen.append("\(request.httpMethod ?? "") \(request.url!.path)")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
            let json = ["Content-Type": "application/json"]
            switch (request.httpMethod ?? "", request.url!.path) {
            case ("GET", "/api/v1/auth/account/deletion"):
                return (200, json, Data(#"{"deletable":true,"restorable":false,"restore_reason":"","blockers":[],"reauth":{"required":true,"methods":["password"]}}"#.utf8))
            case ("POST", "/api/v1/auth/reauth"):
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String]
                XCTAssertEqual(body, ["password": "correct-password", "code": "123456"])
                return (200, json, Data(#"{"verified":true,"expires_in":600}"#.utf8))
            case ("POST", "/api/v1/auth/account/deletion"):
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String]
                XCTAssertEqual(body, ["confirm": "DELETE"])
                return (202, json, Data(#"{"deleted_at":"2026-10-18T10:00:00Z","purge_after":"2027-01-16T10:00:00Z"}"#.utf8))
            default: XCTFail("Unexpected request \(request.url!)"); return (500, json, Data("{}".utf8))
            }
        }
        StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: try ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: configuration),
                                       initialTokens: TokenPair(access: "fixture-access", refresh: "fixture-refresh"))
        let credentials = await service.refresh.snapshot()
        let repository = LiveAccountDeletionRepository(service: service, expectedCredentials: credentials)
        let preview = try await repository.preview(); XCTAssertTrue(preview.deletable)
        let proof = try await repository.reauthenticate(password: "correct-password", code: "123456"); XCTAssertTrue(proof.verified)
        let result = try await repository.delete(); XCTAssertGreaterThan(result.purge_after, result.deleted_at)
        XCTAssertEqual(seen, ["GET /api/v1/auth/account/deletion", "POST /api/v1/auth/reauth", "POST /api/v1/auth/account/deletion"])
    }
}
