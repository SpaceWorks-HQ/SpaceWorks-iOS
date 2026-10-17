import Foundation
import SpaceWorksAPI
import XCTest
@testable import SpaceWorks

final class OwnedRepositoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var callbacks = 0
    var counts: (requests: Int, callbacks: Int) { lock.lock(); defer { lock.unlock() }; return (requests, callbacks) }
    func requested() { lock.lock(); requests += 1; lock.unlock() }
    func notified() { lock.lock(); callbacks += 1; lock.unlock() }
}

struct OwnedRepositoryFixture {
    let service: SpaceWorksService
    let credentials: CredentialSnapshot
    let probe: OwnedRepositoryProbe
    let origin: ServerOrigin
    static func make() async throws -> OwnedRepositoryFixture {
        let probe = OwnedRepositoryProbe()
        StubProtocol.lock.lock()
        StubProtocol.handler = { _ in
            probe.requested(); return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let origin = try ServerOrigin("https://spaceworks.example")
        let service = SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: configuration),
            initialTokens: .init(access: "old-account-access", refresh: "old-account-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7])
        return OwnedRepositoryFixture(service: service, credentials: await service.refresh.snapshot(), probe: probe, origin: origin)
    }
    func replaceAccount() async throws {
        try await service.refresh.install(nil)
        try await service.refresh.install(.init(access: "replacement-account-access", refresh: "replacement-account-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7])
    }
}

final class RepositoryOwnershipTests: XCTestCase {
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func refused(_ work: @Sendable () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await work(); XCTFail("Retired repository used replacement-account authority", file: file, line: line) }
        catch { XCTAssertTrue(APIError.isCancellation(error), "Expected an owner cancellation, received \(error)", file: file, line: line) }
    }
    func testAcceptedRepositoryOwnerSurvivesSameInstallationRefreshRotation() async throws {
        let fixture = try await OwnedRepositoryFixture.make(); let probe = fixture.probe
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            probe.requested()
            if request.url?.path == "/api/v1/auth/device/refresh" {
                return (200, ["Content-Type": "application/json"], Data(DebugAuthFixtures.tokens.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-account-access" {
                return (401, ["Content-Type": "application/json"], Data(#"{"code":"token_expired","detail":"Expired."}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
            return (200, ["Content-Type": "application/json"], Data(DebugMemberFixtures.categories.utf8))
        }
        StubProtocol.lock.unlock()
        let repository = LiveMemberRepository(service: fixture.service, expectedCredentials: fixture.credentials,
            origin: fixture.origin, id: 7, slug: "makerspace-one", onUnauthorized: { _ in probe.notified() })
        _ = try await repository.categories(); _ = try await repository.categories()
        let same = await fixture.service.refresh.isSameInstallation(fixture.credentials)
        XCTAssertTrue(same); XCTAssertEqual(probe.counts.requests, 4); XCTAssertEqual(probe.counts.callbacks, 0)
    }
    func testRetainedMemberRepositoryCannotFirstReadOrMarkInboxUnderReplacementAccount() async throws {
        let fixture = try await OwnedRepositoryFixture.make(); let probe = fixture.probe
        let repository = LiveMemberRepository(service: fixture.service, expectedCredentials: fixture.credentials,
            origin: fixture.origin, id: 7, slug: "makerspace-one", onUnauthorized: { _ in probe.notified() }, onForbidden: { probe.notified() })
        try await fixture.replaceAccount()
        await refused { _ = try await repository.inventory(page: 1, search: "", category: nil) }
        await refused { _ = try await repository.card() }
        await refused { try await repository.markAllRead() }
        XCTAssertEqual(probe.counts.requests, 0); XCTAssertEqual(probe.counts.callbacks, 0)
        let pair = await fixture.service.refresh.current(); XCTAssertEqual(pair?.access, "replacement-account-access")
    }
    func testRetainedMemberActionsCannotFirstMutateUsingReplacementAccount() async throws {
        let fixture = try await OwnedRepositoryFixture.make(); let probe = fixture.probe
        let repository = LiveMemberActionsRepository(service: fixture.service, expectedCredentials: fixture.credentials,
            id: 7, slug: "makerspace-one", onUnauthorized: { _ in probe.notified() }, onForbidden: { probe.notified() })
        try await fixture.replaceAccount()
        await refused { _ = try await repository.renew(request: 601) }
        await refused { _ = try await repository.cancelBooking(token: "opaque-booking") }
        await refused { _ = try await repository.updateProfile(.init(display_name: "Retired edit")) }
        await refused { _ = try await repository.bootstrap() }
        XCTAssertEqual(probe.counts.requests, 0); XCTAssertEqual(probe.counts.callbacks, 0)
    }
    func testRetainedPaymentsCannotReadCreateIntentOrDownloadUnderReplacementAccount() async throws {
        let fixture = try await OwnedRepositoryFixture.make(); let probe = fixture.probe
        let repository = LivePaymentRepository(service: fixture.service, expectedCredentials: fixture.credentials,
            makerspaceID: 7, origin: fixture.origin, onUnauthorized: { _ in probe.notified() }, onForbidden: { probe.notified() })
        try await fixture.replaceAccount()
        await refused { _ = try await repository.payments() }
        await refused { _ = try await repository.intent(paymentID: 501) }
        await refused { _ = try await repository.documents(page: 1) }
        await refused { _ = try await repository.documentPDF(documentID: 901) }
        XCTAssertEqual(probe.counts.requests, 0); XCTAssertEqual(probe.counts.callbacks, 0)
    }
}
