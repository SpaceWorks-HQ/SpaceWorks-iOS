#if DEBUG
import Foundation
import Observation
import SpaceWorksAPI
import XCTest
@testable import SpaceWorks

@MainActor final class AccountCooldownTests: XCTestCase {
    func testCanceledOlderCooldownCannotClearNewerServerDeadline() async throws {
        let readsStarted = expectation(description: "Both account reads reached the server")
        readsStarted.expectedFulfillmentCount = 2
        let firstSleep = expectation(description: "First cooldown entered its sleep")
        let secondSleep = expectation(description: "Replacement cooldown entered its sleep")
        let server = AccountCooldownServer(started: readsStarted)
        AccountCooldownProtocol.server = server
        let sleep = AccountCooldownSleep { index in (index == 0 ? firstSleep : secondSleep).fulfill() }
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [AccountCooldownProtocol.self]
        let session = DeviceSession.make(configuration: configuration)
        let origin = try ServerOrigin("https://account-cooldown.example")
        let service = SpaceWorksService(origin: origin, session: session, initialTokens: .init(access: "sample-access", refresh: "sample-refresh"))
        let repository = LiveAccountRepository(service: service, expectedCredentials: await service.refresh.snapshot(), makerspaceID: nil, origin: origin)
        let account = AccountState(repository: repository, makerspaceID: nil, makerspaceName: "", cooldownSleep: { try await sleep.wait($0) })
        defer {
            account.invalidate(); session.invalidateAndCancel(); AccountCooldownProtocol.server = nil
            Task { await sleep.releaseAll() }
        }
        let security = Task { await account.loadSecurity() }
        let providers = Task { await account.loadProviders() }
        await fulfillment(of: [readsStarted], timeout: 5)
        let securityReply = try XCTUnwrap(server.request("/api/v1/auth/mfa"))
        let providersReply = try XCTUnwrap(server.request("/api/v1/auth/social/providers"))
        securityReply.reject(retryAfter: 60)
        await fulfillment(of: [firstSleep], timeout: 5)
        let firstDeadline = account.retryAfter
        providersReply.reject(retryAfter: 120)
        await fulfillment(of: [secondSleep], timeout: 5)
        await security.value; await providers.value
        let newerDeadline = account.retryAfter
        XCTAssertGreaterThan(newerDeadline, firstDeadline)
        XCTAssertFalse(account.canRequest)

        let oldTimerChangedDeadline = expectation(description: "Canceled timer must not change newer deadline")
        oldTimerChangedDeadline.isInverted = true
        withObservationTracking { _ = account.retryAfter } onChange: { oldTimerChangedDeadline.fulfill() }
        // Model a normal sleep completion racing cancellation. The loop then observes cancellation.
        await sleep.release(0)
        await fulfillment(of: [oldTimerChangedDeadline], timeout: 0.1)
        XCTAssertEqual(account.retryAfter, newerDeadline)
        XCTAssertFalse(account.canRequest)
        account.invalidate(); await sleep.releaseAll()
        XCTAssertFalse(account.isActive); XCTAssertFalse(account.canRequest)
    }
}

private actor AccountCooldownSleep {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var count = 0
    private let started: @Sendable (Int) -> Void
    init(started: @escaping @Sendable (Int) -> Void) { self.started = started }
    func wait(_ nanoseconds: UInt64) async throws {
        XCTAssertGreaterThan(nanoseconds, 0)
        let index = count; count += 1
        await withCheckedContinuation { continuations[index] = $0; started(index) }
    }
    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume() }
    func releaseAll() { let held = continuations.values; continuations = [:]; held.forEach { $0.resume() } }
}

private final class AccountCooldownServer: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: AccountCooldownProtocol] = [:]
    private let started: XCTestExpectation
    init(started: XCTestExpectation) { self.started = started }
    func receive(_ request: AccountCooldownProtocol) {
        lock.lock(); requests[request.request.url!.path] = request; lock.unlock(); started.fulfill()
    }
    func request(_ path: String) -> AccountCooldownProtocol? { lock.lock(); defer { lock.unlock() }; return requests[path] }
}

private final class AccountCooldownProtocol: URLProtocol, @unchecked Sendable {
    static var server: AccountCooldownServer?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.server?.receive(self) }
    override func stopLoading() {}
    func reject(retryAfter: Int) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Retry-After": String(retryAfter)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"detail":"Too many requests. Try again later."}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
