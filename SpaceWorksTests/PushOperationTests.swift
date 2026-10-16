import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

final class PushOperationTests: XCTestCase {
    private let origin = try! ServerOrigin("https://push.example")
    private let token = String(repeating: "ab", count: 32)
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func service(memberships: Set<Int> = [7, 8], handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)) async throws -> SpaceWorksService {
        StubProtocol.lock.lock(); StubProtocol.handler = handler; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: configuration), initialTokens: .init(access: "fixture-access", refresh: "fixture-refresh"))
        try await service.makerspace.select(7, activeMemberships: memberships)
        return service
    }
    func testGeneratedRegistrationSupportsBothSuccessStatusesAndDeleteUsesActualReturnedIDWithoutChangingSelectedMaker() async throws {
        let calls = PushOperationCounter()
        let service = try await service { request in
            let count = calls.next()
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "8")
            for key in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: key)) }
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/api/v1/integrations/push/devices/801")
                return (204, [:], Data())
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/integrations/push/devices")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String])
            XCTAssertEqual(Set(json.keys), ["token", "provider", "environment"])
            XCTAssertEqual(json["token"], self.token); XCTAssertEqual(json["provider"], "apns"); XCTAssertEqual(json["environment"], "development")
            let body = #"{"id":801,"provider":"apns","environment":"development","makerspace_id":8,"active":true,"created_at":"2026-10-16T09:00:00Z","updated_at":"2026-10-16T09:00:00Z"}"#
            return (count == 1 ? 201 : 200, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let repository = LivePushRegistrationRepository(service: service, expectedCredentials: await service.refresh.snapshot())
        for _ in 0..<2 {
            let row = try await repository.register(makerspaceID: 8, token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8])
            XCTAssertEqual(row.id, 801)
        }
        try await repository.unregister(makerspaceID: 8, deviceID: 801, authorizedDirectMembershipIDs: [7, 8])
        let selected = await service.makerspace.current()
        XCTAssertEqual(selected, 7); XCTAssertEqual(calls.value, 3)
    }
    func testOldAccountWorkerCannotRegisterOrCleanUpUsingReplacementAccountCredentials() async throws {
        let calls = PushOperationCounter()
        let service = try await service { _ in _ = calls.next(); return (500, [:], Data()) }
        let repository = LivePushRegistrationRepository(service: service, expectedCredentials: await service.refresh.snapshot())
        try await service.refresh.install(.init(access: "new-account", refresh: "new-account-refresh"))
        do { _ = try await repository.register(makerspaceID: 7, token: token, environment: "development", authorizedDirectMembershipIDs: [7, 8]); XCTFail("Old owner registered using a new account") }
        catch { XCTAssertTrue(PushOperationFailure.isCancellation(error)) }
        do { try await repository.unregister(makerspaceID: 7, deviceID: 701, authorizedDirectMembershipIDs: [7, 8]); XCTFail("Old owner cleaned up using a new account") }
        catch { XCTAssertTrue(PushOperationFailure.isCancellation(error)) }
        XCTAssertEqual(calls.value, 0)
    }
    func testBackgroundPushScopeCannotBeUsedForAnOrdinaryAuthenticatedOperation() async throws {
        let calls = PushOperationCounter()
        let service = try await service { _ in _ = calls.next(); return (500, [:], Data()) }
        do {
            _ = try await service.withPushMakerspace(8, authorizedDirectMembershipIDs: [7, 8]) { try await service.me() }
            XCTFail("Background push authorization escaped to an ordinary operation")
        } catch { XCTAssertEqual(calls.value, 0) }
        let selected = await service.makerspace.current(); XCTAssertEqual(selected, 7)
    }
    func testCallerSuppliedMembershipSetCannotGrantUnknownMakerspaceAndDelete404IsAlreadyClean() async throws {
        let calls = PushOperationCounter()
        let service = try await service(memberships: [7]) { request in
            _ = calls.next()
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (404, ["Content-Type": "application/json"], Data(#"{"detail":"Not found.","code":"not_found"}"#.utf8))
        }
        let repository = LivePushRegistrationRepository(service: service, expectedCredentials: await service.refresh.snapshot())
        do { _ = try await repository.register(makerspaceID: 8, token: token, environment: "development", authorizedDirectMembershipIDs: [8]); XCTFail("Unknown membership was accepted") }
        catch { XCTAssertEqual(calls.value, 0) }
        try await repository.unregister(makerspaceID: 7, deviceID: 701, authorizedDirectMembershipIDs: [7])
        XCTAssertEqual(calls.value, 1)
    }
}

private final class PushOperationCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
