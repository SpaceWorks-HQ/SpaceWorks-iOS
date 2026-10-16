import XCTest
import Foundation
import SpaceWorksAPI

final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock()
            let block = Self.handler
            Self.lock.unlock()
            let (code, headers, data) = try XCTUnwrap(block)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class NetworkingTests: XCTestCase {
    private let origin = try! ServerOrigin("https://spaceworks.example")
    private let json = ["Content-Type": "application/json"]
    private func service(tokens: TokenPair? = nil, handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)) -> SpaceWorksService {
        StubProtocol.lock.lock()
        StubProtocol.handler = handler
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration()
        config.protocolClasses = [StubProtocol.self]
        return SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: config), initialTokens: tokens)
    }
    override func tearDown() {
        StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock()
    }

    func testHealthUsesGeneratedPathAndNoBrowserHeaders() async throws {
        let client = service { request in
            XCTAssertEqual(request.url?.absoluteString, "https://spaceworks.example/api/v1/health/")
            XCTAssertEqual(request.httpMethod, "GET")
            for name in ["Cookie", "Origin", "Referer", "Authorization", "X-Makerspace-Id"] { XCTAssertNil(request.value(forHTTPHeaderField: name)) }
            return (200, self.json, Data(#"{"status":"ok"}"#.utf8))
        }
        try await client.health()
        let config = DeviceSession.configuration()
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
    }

    func testConcurrent401sRotateExactlyOnceAndPublishBeforeAllRetries() async throws {
        let counter = LockedCounter()
        let old = TokenPair(access: "old-access", refresh: "old-refresh")
        let client = service(tokens: old) { request in
            if request.url!.path == "/api/v1/auth/device/refresh" {
                counter.increment()
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                for name in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: name)) }
                let data = requestBody(request)
                let body = try JSONSerialization.jsonObject(with: data) as! [String: String]
                XCTAssertEqual(body, ["refresh": "old-refresh"])
                Thread.sleep(forTimeInterval: 0.1)
                return (200, self.json, Data(Self.rotated.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
                return (401, self.json, Data(#"{"detail":"Expired","code":"token_expired"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return (200, self.json, Data(#"{"status":"ok"}"#.utf8))
        }
        try await client.makerspace.select(7, activeMemberships: [7])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await client.health()
                    let pair = await client.refresh.current()
                    XCTAssertEqual(pair, TokenPair(access: "new-access", refresh: "new-refresh"))
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(counter.value, 1)
        // A late response rejected with the old access token must not rotate again.
        let recovered = try await client.refresh.recover(rejectedAccess: "old-access")
        XCTAssertEqual(recovered.refresh, "new-refresh")
        XCTAssertEqual(counter.value, 1)
    }

    func testRefreshFailureSignsOutWithoutReusingRefreshToken() async throws {
        let counter = LockedCounter()
        let client = service(tokens: TokenPair(access: "old", refresh: "single-use")) { request in
            if request.url!.path.contains("refresh") { counter.increment() }
            return (401, self.json, Data(#"{"detail":"Sign in again.","code":"revoked"}"#.utf8))
        }
        do { try await client.health(); XCTFail("Expected failure") }
        catch { XCTAssertEqual(APIError.display(error), "Sign in again.") }
        let pair = await client.refresh.current()
        XCTAssertNil(pair)
        do { try await client.health(); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(counter.value, 1)
    }

    func testErrorsPreserveDetailAndRetryAfterWithoutAutomaticRetry() async throws {
        let counter = LockedCounter()
        let client = service { _ in
            counter.increment()
            return (429, ["Content-Type": "application/json", "Retry-After": "120"], Data(#"{"detail":"Slow down.","code":"throttled"}"#.utf8))
        }
        do { try await client.health(); XCTFail("Expected throttling") }
        catch {
            XCTAssertEqual(APIError.display(error), "Slow down.")
            XCTAssertGreaterThan(try XCTUnwrap(APIError.retryDeadline(error)).timeIntervalSinceNow, 110)
        }
        XCTAssertEqual(counter.value, 1)
    }

    func testErrorFallbacksAndSpecialCodes() async throws {
        for (status, text) in [(400, "Check the details and try again."), (401, "Please sign in again."), (403, "You do not have permission to do this."), (404, "This item wasn't found."), (409, "This changed. Refresh and try again."), (429, "Too many requests. Try again later."), (503, "The server is unavailable. Try again later.")] {
            let client = service { _ in (status, self.json, Data(#"{"detail":" ","code":"unknown"}"#.utf8)) }
            do { try await client.health(); XCTFail("Expected error") }
            catch { XCTAssertEqual(APIError.display(error), text) }
        }
        XCTAssertEqual(APIError(status: 403, code: "device_superadmin_not_supported", detail: "Ignored").errorDescription, "Use the web console")
        XCTAssertEqual(APIError(status: 409, code: "payment_rail_conflict", detail: "Ignored").errorDescription, "Finish this payment on the web.")
        XCTAssertEqual(APIError(status: 503, code: "payments_unavailable", detail: "Ignored").errorDescription, "Online payment is unavailable. Try again later or pay at the desk.")
    }

    func testFrameworkAndValidationErrorsKeepServerMessages() async throws {
        for (status, body, expected) in [
            (403, #"{"detail":"Membership is inactive."}"#, "Membership is inactive."),
            (400, #"{"email":["Enter a valid email."],"name":["This field is required."]}"#, "email: Enter a valid email.\nname: This field is required."),
            (403, #"{"code":"device_superadmin_not_supported"}"#, "Use the web console")
        ] {
            let client = service { _ in (status, self.json, Data(body.utf8)) }
            do { try await client.health(); XCTFail("Expected error") }
            catch { XCTAssertEqual(APIError.display(error), expected) }
        }
    }

    func testOriginAndPaginationRejectCredentialLeaks() throws {
        for value in ["http://example.com", "https://user:password@example.com", "https://example.com/api/v1", "https://example.com?q=1", "ftp://example.com", "https://example.com/#fragment"] { XCTAssertThrowsError(try ServerOrigin(value)) }
        XCTAssertNoThrow(try ServerOrigin("http://localhost:8000", allowLocalHTTP: true))
        XCTAssertThrowsError(try ServerOrigin("http://example.com", allowLocalHTTP: true))
        XCTAssertEqual(try origin.nextPage("/api/v1/items?page=2")?.absoluteString, "https://spaceworks.example/api/v1/items?page=2")
        XCTAssertNoThrow(try origin.nextPage("https://spaceworks.example:443/api/v1/items?page=2"))
        XCTAssertNil(try origin.nextPage(nil))
        for next in ["https://attacker.example/api/items", "http://spaceworks.example/api/items", "//evil.example/api/items", "https://user@spaceworks.example/api/items", "/admin", "/api/../admin", "https://spaceworks.example:8443/api/items"] { XCTAssertThrowsError(try origin.nextPage(next)) }
    }

    func testMakerspaceRequiresActiveMembership() async throws {
        let context = MakerspaceContext()
        do { try await context.select(42, activeMemberships: [7]); XCTFail("Expected rejection") } catch {}
        let selected = await context.current()
        XCTAssertNil(selected)
    }

    func testRedirectDelegateRefusesCrossOriginAndDowngrade() {
        let delegate = NoRedirectDelegate()
        let session = DeviceSession.make()
        let task = session.dataTask(with: origin.url)
        for target in ["https://evil.example/api/v1/health/", "http://spaceworks.example/api/v1/health/"] {
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: origin.url, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: target)!)) { redirected in
                XCTAssertNil(redirected)
            }
        }
        session.invalidateAndCancel()
    }

    private static let rotated = #"{"access":"new-access","refresh":"new-refresh","device_grant":{"id":"0c20b5af-5915-4d3d-8d4b-165b16874076","platform":"ios","app_id":"org.spaceworks.app","environment":"development","status":"active","attested_at":"2026-10-16T00:00:00Z","last_used_at":"2026-10-16T00:00:00Z","created_at":"2026-10-16T00:00:00Z"}}"#
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

func requestBody(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n <= 0 { break }
        result.append(contentsOf: buffer.prefix(n))
    }
    return result
}
