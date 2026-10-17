import Foundation
import SpaceWorksAPI
import XCTest
@testable import SpaceWorks

final class AccountOperationTests: XCTestCase {
    private let origin = try! ServerOrigin("https://spaceworks.example")
    private let jobID = "84000000-0000-4000-8000-000000000001"
    private let grantID = "83000000-0000-4000-8000-000000000001"
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func repository(makerspaceID: Int? = 7, handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)) async throws -> LiveAccountRepository {
        StubProtocol.lock.lock(); StubProtocol.handler = handler; StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: config), initialTokens: .init(access: "account-access", refresh: "account-refresh"))
        try await service.makerspace.select(makerspaceID, activeMemberships: makerspaceID == nil ? [] : [7, 9])
        return .init(service: service, expectedCredentials: await service.refresh.snapshot(), makerspaceID: makerspaceID, origin: origin)
    }
    private func json(_ value: String, status: Int = 200) -> (Int, [String: String], Data) { (status, ["Content-Type": "application/json"], Data(value.utf8)) }
    private func data(_ value: String, changes: [String: Any]) throws -> String {
        var object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any]; object.merge(changes) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private var me: String { #"{"id":51,"username":"meera","email":"meera@example.test","display_name":"Meera Nair","phone":"","email_verified":true,"role":"member","is_superuser":false,"must_change_password":false,"makerspaces":[]}"# }
    private func archiveBytes() throws -> Data {
        let object = try JSONSerialization.jsonObject(with: Data(DebugAccountFixtures.archive.utf8)) as! [String: String]
        return try XCTUnwrap(Data(base64Encoded: object["base64"]!))
    }
    func testGlobalSecurityOwnerCanCleanNativePushAndRestoreGlobalHeaderScope() async throws {
        let count = AccountCallCounter()
        let repo = try await repository { request in
            count.increment()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-access")
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/integrations/push/devices/901")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "9")
                return (204, [:], Data())
            }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            return self.json(self.me)
        }
        let push = LivePushRegistrationRepository(service: repo.service, expectedCredentials: repo.expectedCredentials)
        try await repo.service.withSession(expectedCredentials: repo.expectedCredentials) {
            try await push.unregister(makerspaceID: 9, deviceID: 901, authorizedDirectMembershipIDs: [7, 9])
            _ = try await repo.service.me()
            do {
                _ = try await repo.service.withPushMakerspace(9, authorizedDirectMembershipIDs: [7, 9], expectedCredentials: repo.expectedCredentials) { try await repo.service.me() }
                XCTFail("Narrow cleanup scope allowed an ordinary account operation")
            } catch { XCTAssertTrue(PushOperationFailure.isCancellation(error)) }
        }
        XCTAssertEqual(count.value, 2)
        let selected = await repo.service.makerspace.current(); XCTAssertEqual(selected, 7)
    }
    func testPasswordChangeUsesExistingGeneratedGlobalOperationAndDoesNotInventTokenRotation() async throws {
        let count = AccountCallCounter()
        let repo = try await repository(makerspaceID: nil) { request in
            count.increment()
            if request.url?.path == "/api/v1/auth/me" {
                XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
                return self.json(self.me)
            }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/change-password")
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-access")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String])
            XCTAssertEqual(body, ["current_password": "DemoPass!123", "new_password": "NewDemoPassword!"])
            return self.json(#"{"detail":"Password updated."}"#)
        }
        try await repo.changePassword(current: "DemoPass!123", new: "NewDemoPassword!")
        let pair = await repo.service.refresh.current(); XCTAssertEqual(pair, TokenPair(access: "account-access", refresh: "account-refresh")); XCTAssertEqual(count.value, 2)
    }
    func testPasswordAcknowledgementThenIdentity401RemainsSessionRefusal() async throws {
        let ended = AccountCallCounter()
        var repo = try await repository(makerspaceID: nil) { request in
            if request.url?.path == "/api/v1/auth/change-password" { return self.json(#"{"detail":"Password updated."}"#) }
            if request.url?.path == "/api/v1/auth/device/refresh" { return self.json(DeviceRefreshFixture.rotated) }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/me")
            return self.json(#"{"detail":"Session revoked."}"#, status: 401)
        }
        repo.onUnauthorized = { _ in ended.increment() }
        do { try await repo.changePassword(current: "DemoPass!123", new: "NewDemoPassword!"); XCTFail("Expired identity accepted after acknowledgement") }
        catch { XCTAssertEqual(APIError.status(error), 401); XCTAssertNotEqual(APIError.code(error), "password_verification_failed") }
        XCTAssertEqual(ended.value, 1)
    }
    func testAll21GeneratedAccountOperationsUseExactBodiesAndPublicArchiveHasNoAccountCredentials() async throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let refreshed = try decoder.decode(Components.Schemas.DeviceRefreshResponse.self, from: Data(DeviceRefreshFixture.rotated.utf8))
        XCTAssertEqual(refreshed.access, "rotated-access"); XCTAssertEqual(refreshed.refresh, "rotated-refresh")
        XCTAssertEqual(refreshed.device_grant.app_id, "org.spaceworks.app")
        var calls = Set<String>(); var grantsIssued = 0
        let zip = try archiveBytes()
        let repo = try await repository { request in
            let path = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); let method = request.httpMethod!
            calls.insert(method + " " + path)
            if path.contains("data-exports/download/") {
                XCTAssertEqual(method, "GET"); XCTAssertTrue(path.hasSuffix("one-use-2"))
                for key in ["Authorization", "X-Makerspace-Id", "Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: key)) }
                return (200, ["Content-Type": "application/zip"], zip)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), path.hasPrefix("api/v1/auth/") ? nil : "7")
            for key in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: key)) }
            if method == "DELETE" {
                XCTAssertTrue(requestBody(request).isEmpty)
                if path.hasSuffix("auth/phone") { return self.json(#"{"phone_e164":"","verified":false}"#) }
                return (204, [:], Data())
            }
            if path.hasSuffix("auth/device/grants") { return self.json(DebugAccountFixtures.grants) }
            if path.hasSuffix("account/sessions") { XCTAssertNil(request.url?.query); return self.json(DebugAccountFixtures.sessions) }
            if path.hasSuffix("account/membership") { return self.json(DebugAccountFixtures.membership) }
            if path.hasSuffix("account/leave") || path.hasSuffix("account/cancel") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["reason"] as? String, "Moving away"); return self.json(DebugAccountFixtures.membership)
            }
            if path.hasSuffix("account/exports") {
                if method == "POST" {
                    let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]; XCTAssertTrue(body.isEmpty)
                    return self.json(DebugAccountFixtures.export, status: 202)
                }
                XCTAssertNil(request.url?.query); return self.json("{\"count\":1,\"next\":null,\"previous\":null,\"results\":[\(DebugAccountFixtures.export)]}")
            }
            if path.hasSuffix("/\(self.jobID)/download") {
                XCTAssertEqual(method, "POST"); XCTAssertTrue(requestBody(request).isEmpty); grantsIssued += 1
                return self.json("{\"url\":\"https://spaceworks.example/api/v1/data-exports/download/\(self.jobID)/one-use-\(grantsIssued)\",\"expires_at\":\"2099-01-01T00:00:00Z\"}")
            }
            if path.hasSuffix("account/exports/\(self.jobID)") { return self.json(DebugAccountFixtures.export) }
            if path.hasSuffix("auth/mfa") { return self.json(method == "POST" ? DebugAccountFixtures.challenge : DebugAccountFixtures.mfa) }
            if path.hasSuffix("mfa/disable") || path.hasSuffix("mfa/recovery") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]; XCTAssertEqual(body["password"] as? String, "fixture-password")
                return self.json(path.hasSuffix("recovery") ? DebugAccountFixtures.recovery : DebugAccountFixtures.mfa)
            }
            if path.hasSuffix("phone/link/start") || path.hasSuffix("phone/link/confirm") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]; XCTAssertEqual(body["phone"] as? String, "+919876543210")
                if path.hasSuffix("confirm") { XCTAssertEqual(body["code"] as? String, "123456"); return self.json(#"{"phone_e164":"+919876543210","verified":true}"#) }
                return self.json(#"{"detail":"Code sent."}"#)
            }
            if path.hasSuffix("social/providers") { return self.json("[\(DebugAccountFixtures.provider)]") }
            XCTFail("Unexpected account route \(method) \(path)"); return self.json("{}", status: 500)
        }
        _ = try await repo.grants(); try await repo.revokeGrant(id: grantID)
        _ = try await repo.sessions(page: 1); try await repo.revokeSession(id: "web:sample-other-session")
        _ = try await repo.membership(); _ = try await repo.leave(reason: "Moving away"); _ = try await repo.cancelRenewal(reason: "Moving away")
        _ = try await repo.exports(page: 1); _ = try await repo.requestExport(); _ = try await repo.export(id: jobID); _ = try await repo.exportDownload(id: jobID)
        let bytes = try await repo.exportArchive(id: jobID); XCTAssertEqual(bytes, zip)
        _ = try await repo.mfa()
        _ = try await repo.service.withSession { try await repo.service.accountStartMFA(password: "fixture-password") } // Generated seam; native UI/repository gates it.
        _ = try await repo.disableMFA(password: "fixture-password"); _ = try await repo.regenerateRecovery(password: "fixture-password")
        _ = try await repo.startPhone(phone: "+919876543210"); _ = try await repo.confirmPhone(phone: "+919876543210", code: "123456"); _ = try await repo.unlinkPhone()
        _ = try await repo.providers(); try await repo.unlinkProvider("google")
        XCTAssertEqual(calls.count, 21); XCTAssertEqual(grantsIssued, 2)
    }
    func testGlobalScopeStripsSelectedMakerAndCannotEscapeToMemberOrPushOverride() async throws {
        let count = AccountCallCounter()
        let repo = try await repository { request in
            count.increment(); XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-access")
            return self.json(self.me)
        }
        _ = try await repo.service.withSession { try await repo.service.me() }
        do { _ = try await repo.service.withSession { try await repo.service.memberPayments(makerspaceID: 7) }; XCTFail("Global scope escaped to member data") }
        catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        do {
            _ = try await repo.service.withPushMakerspace(9, authorizedDirectMembershipIDs: [7, 9]) {
                try await repo.service.withSession { try await repo.service.me() }
            }
            XCTFail("Push override escaped into global security")
        } catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        XCTAssertEqual(count.value, 1)
        let selected = await repo.service.makerspace.current(); XCTAssertEqual(selected, 7)
    }
    func testQueuedGlobalSecurityActionCannotSendUnderReplacementAccount() async throws {
        let gate = AccountScopeGate(); let count = AccountCallCounter()
        let repo = try await repository { _ in count.increment(); return self.json(DebugAccountFixtures.mfa) }
        let old = Task { try await repo.service.withSession { await gate.arrive(); return try await repo.service.withSession { try await repo.service.accountMFA() } } }
        await gate.entered()
        try await repo.service.refresh.install(.init(access: "new-account", refresh: "new-refresh"))
        await gate.release()
        do { _ = try await old.value; XCTFail("Old security action sent under replacement account") }
        catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        XCTAssertEqual(count.value, 0)
    }
    func testRetainedAccountRepositoryCannotSendOrEndReplacementSession() async throws {
        let count = AccountCallCounter(), ended = AccountCallCounter()
        var repo = try await repository(makerspaceID: nil) { _ in count.increment(); return self.json(DebugAccountFixtures.mfa) }
        repo.onUnauthorized = { _ in ended.increment() }
        try await repo.service.refresh.install(.init(access: "replacement-access", refresh: "replacement-refresh"))
        do { _ = try await repo.mfa(); XCTFail("Retained repository used replacement credentials") }
        catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        do { _ = try await repo.regenerateRecovery(password: "old-password"); XCTFail("Old management mutation used replacement account") }
        catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        XCTAssertEqual(count.value, 0); XCTAssertEqual(ended.value, 0)
    }
    func testLateManagement401NeverProbesOrSignsOutReplacementAccount() async throws {
        let entryOrCompletion = expectation(description: "Retried response arrived or operation finished")
        let finalResponse = AccountResponseGate(entryOrCompletion: entryOrCompletion)
        let calls = AccountCallCounter(), ended = AccountCallCounter(), probes = AccountCallCounter()
        var repo = try await repository(makerspaceID: nil) { request in
            if request.url?.path == "/api/v1/auth/device/refresh" { return self.json(DeviceRefreshFixture.rotated) }
            if request.url?.path == "/api/v1/auth/me" { probes.increment(); return self.json(self.me) }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/mfa/recovery")
            calls.increment()
            if calls.value == 2 { finalResponse.block() }
            return self.json(#"{"detail":"Password verification failed."}"#, status: 401)
        }
        repo.onUnauthorized = { _ in ended.increment() }
        let owner = repo
        let old = Task {
            defer { finalResponse.operationCompleted() }
            return try await owner.regenerateRecovery(password: "old-password")
        }
        defer { finalResponse.release(); old.cancel() }
        await fulfillment(of: [entryOrCompletion], timeout: 5)
        guard finalResponse.didEnter else {
            finalResponse.release()
            // An early decode/transport failure must surface instead of waiting for an unreachable retry.
            _ = try await old.value
            XCTFail("Management operation finished without its held retry")
            return
        }
        try await repo.service.refresh.install(.init(access: "replacement-access", refresh: "replacement-refresh"))
        finalResponse.release()
        do { _ = try await old.value; XCTFail("Old management result accepted") }
        catch { XCTAssertTrue(AccountOperationFailure.isCancellation(error)) }
        XCTAssertEqual(calls.value, 2); XCTAssertEqual(probes.value, 0); XCTAssertEqual(ended.value, 0)
        let pair = await repo.service.refresh.current(); XCTAssertEqual(pair?.access, "replacement-access")
    }
    func testGlobalOperationsUseBearerWithoutMakerWhenThereIsNoMembership() async throws {
        let count = AccountCallCounter()
        let repo = try await repository(makerspaceID: nil) { request in
            count.increment(); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-access")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Makerspace-Id"))
            let path = request.url!.path
            if path.hasSuffix("/grants") { return self.json(DebugAccountFixtures.grants) }
            if path.hasSuffix("/mfa") { return self.json(DebugAccountFixtures.mfa) }
            if path.hasSuffix("/providers") { return self.json("[\(DebugAccountFixtures.provider)]") }
            if path.hasSuffix("/me") { return self.json(self.me) }
            XCTFail("Unexpected global account operation"); return self.json("{}", status: 500)
        }
        _ = try await repo.grants(); _ = try await repo.mfa(); _ = try await repo.providers(); try await repo.validateSession()
        XCTAssertEqual(count.value, 4)
        do { _ = try await repo.sessions(page: 1); XCTFail("No-maker member session request") } catch {}
        do { _ = try await repo.membership(); XCTFail("No-maker membership request") } catch {}
        do { _ = try await repo.exports(page: 1); XCTFail("No-maker export request") } catch {}
        do { _ = try await repo.leave(reason: "Moving away"); XCTFail("No-maker leave request") } catch {}
        XCTAssertEqual(count.value, 4)
    }
    @MainActor func testVeryLargeRetryAfterRetainsDeadlineWithoutOverflowOrRepeatedRequests() async throws {
        let count = AccountCallCounter()
        let repo = try await repository(makerspaceID: nil) { _ in
            count.increment()
            return (429, ["Content-Type": "application/json", "Retry-After": "315360000000"], Data(#"{"detail":"Try again later."}"#.utf8))
        }
        let state = AccountState(repository: repo, makerspaceID: nil, makerspaceName: "")
        await state.loadSecurity(); await Task.yield()
        XCTAssertFalse(state.canRequest); XCTAssertGreaterThan(state.retryAfter, Date().addingTimeInterval(315_000_000_000))
        await state.loadSecurity(); await state.loadGrants(); XCTAssertEqual(count.value, 1)
        state.invalidate()
    }
    @MainActor func testResource403PurgesPrivateDataButDoesNotPermanentlyDisableValidGlobalAccount() async throws {
        let repo = try await repository(makerspaceID: nil) { request in
            if request.url?.path.hasSuffix("/grants") == true { return self.json(#"{"detail":"Device management is unavailable."}"#, status: 403) }
            return self.json(DebugAccountFixtures.mfa)
        }
        let state = AccountState(repository: repo, makerspaceID: nil, makerspaceName: "")
        await state.loadSecurity(); XCTAssertNotNil(state.mfa)
        await state.loadGrants(); XCTAssertTrue(state.isActive); XCTAssertNil(state.mfa); XCTAssertTrue(state.grants.isEmpty)
        await state.loadSecurity(); XCTAssertNotNil(state.mfa); XCTAssertEqual(state.securityLoad, .ready)
    }
    func testLiveMFAStartAndUndocumentedPaginationFailBeforeAnyRequest() async throws {
        let count = AccountCallCounter()
        let repo = try await repository { _ in count.increment(); return self.json("{}") }
        do { _ = try await repo.startMFA(password: "fixture-password"); XCTFail("Native start bypassed browser-only backend gate") }
        catch { XCTAssertEqual(APIError.code(error), "native_mfa_management_unavailable") }
        do { _ = try await repo.sessions(page: 2); XCTFail("Invented session query") } catch { XCTAssertEqual(APIError.code(error), "account_pagination_unavailable") }
        do { _ = try await repo.exports(page: 2); XCTFail("Invented export query") } catch { XCTAssertEqual(APIError.code(error), "account_pagination_unavailable") }
        XCTAssertEqual(count.value, 0)
    }
    @MainActor func testWrongPassword401RefreshesThenProbesIdentityWithoutDestroyingAccountState() async throws {
        let ended = AccountCallCounter(); let refreshes = AccountCallCounter(); let checks = AccountCallCounter()
        var repo = try await repository { request in
            if request.url?.path == "/api/v1/auth/device/refresh" { refreshes.increment(); return self.json(DeviceRefreshFixture.rotated) }
            if request.url?.path == "/api/v1/auth/me" { checks.increment(); return self.json(self.me) }
            if request.url?.path == "/api/v1/auth/mfa" { return self.json(DebugAccountFixtures.mfa) }
            XCTAssertEqual(request.url?.path, "/api/v1/auth/mfa/recovery")
            return self.json(#"{"detail":"Password verification failed."}"#, status: 401)
        }
        repo.onUnauthorized = { _ in ended.increment() }
        let state = AccountState(repository: repo, makerspaceID: 7, makerspaceName: "Sample", endSession: { _, _ in ended.increment() })
        await state.loadSecurity(); state.password = "incorrect"; await state.regenerateRecovery()
        XCTAssertTrue(state.isActive); XCTAssertNotNil(state.mfa); XCTAssertNotNil(state.error); XCTAssertEqual(state.password, "")
        XCTAssertEqual(ended.value, 0); XCTAssertEqual(refreshes.value, 1); XCTAssertEqual(checks.value, 1)
    }
    @MainActor func testUnavailablePasswordIdentityProbeKeepsAccountActionableAndHonorsRetryAfter() async throws {
        let ended = AccountCallCounter(), count = AccountCallCounter()
        var repo = try await repository(makerspaceID: nil) { request in
            count.increment()
            if request.url?.path == "/api/v1/auth/device/refresh" { return self.json(DeviceRefreshFixture.rotated) }
            if request.url?.path == "/api/v1/auth/me" { return (503, ["Content-Type": "application/json", "Retry-After": "17"], Data(#"{"detail":"Identity is temporarily unavailable."}"#.utf8)) }
            if request.url?.path == "/api/v1/auth/mfa" { return self.json(DebugAccountFixtures.mfa) }
            return self.json(#"{"detail":"Password verification failed."}"#, status: 401)
        }
        repo.onUnauthorized = { _ in ended.increment() }
        let state = AccountState(repository: repo, makerspaceID: nil, makerspaceName: "")
        await state.loadSecurity(); state.password = "incorrect"; await state.regenerateRecovery()
        XCTAssertTrue(state.isActive); XCTAssertNotNil(state.mfa); XCTAssertEqual(state.error, "Identity is temporarily unavailable.")
        XCTAssertGreaterThan(state.retryAfter, Date().addingTimeInterval(15)); XCTAssertEqual(ended.value, 0)
        let calls = count.value; state.password = "incorrect"; await state.regenerateRecovery(); XCTAssertEqual(count.value, calls)
        state.invalidate()
    }
    func testOldAccountScopeCannotRevokeAnySessionAfterMakerspaceSwitch() async throws {
        let count = AccountCallCounter(); let repo = try await repository { _ in count.increment(); return (204, [:], Data()) }
        try await repo.service.makerspace.select(9, activeMemberships: [7, 9])
        do { try await repo.revokeSession(id: "web:any-opaque-session"); XCTFail("Old scope sent a revoke") } catch { XCTAssertEqual(count.value, 0) }
    }
    func testForeignOrExpiredExportGrantNeverReachesItsDownloadURL() async throws {
        for url in ["https://evil.example/api/v1/data-exports/download/\(jobID)/token", "https://spaceworks.example/api/v1/data-exports/download/\(jobID)/token?copy=1", "https://spaceworks.example/api/v1/data-exports/download/\(jobID)/%2E%2E"] {
            let count = AccountCallCounter()
            let repo = try await repository { request in
                count.increment(); XCTAssertTrue(request.url!.path.hasSuffix("/download"))
                return self.json("{\"url\":\"\(url)\",\"expires_at\":\"2099-01-01T00:00:00Z\"}")
            }
            do { _ = try await repo.exportArchive(id: jobID); XCTFail("Unsafe grant consumed") } catch { XCTAssertEqual(count.value, 1) }
        }
    }
    func testOctetStreamArchiveUsesSameGeneratedPublicOperation() async throws {
        let zip = try archiveBytes(); let repo = try await repository { request in
            if request.url!.path.hasSuffix("/download") { return self.json("{\"url\":\"https://spaceworks.example/api/v1/data-exports/download/\(self.jobID)/one-use\",\"expires_at\":\"2099-01-01T00:00:00Z\"}") }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); return (200, ["Content-Type": "application/octet-stream"], zip)
        }
        let result = try await repo.exportArchive(id: jobID); XCTAssertEqual(result, zip)
    }
}

private final class AccountCallCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private actor AccountScopeGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func arrive() async { started = true; observer?.resume(); observer = nil; await withCheckedContinuation { continuation = $0 } }
    func entered() async { if !started { await withCheckedContinuation { observer = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
}

private final class AccountResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private let response = DispatchSemaphore(value: 0)
    private let entryOrCompletion: XCTestExpectation
    private var started = false
    private var signaled = false
    init(entryOrCompletion: XCTestExpectation) { self.entryOrCompletion = entryOrCompletion }
    var didEnter: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func block() {
        lock.lock(); started = true; lock.unlock()
        signal()
        XCTAssertEqual(response.wait(timeout: .now() + 10), .success, "Held management response was not released")
    }
    func operationCompleted() { signal() }
    private func signal() {
        lock.lock(); let shouldSignal = !signaled; signaled = true; lock.unlock()
        if shouldSignal { entryOrCompletion.fulfill() }
    }
    func release() { response.signal() }
}
