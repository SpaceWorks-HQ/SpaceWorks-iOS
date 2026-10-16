import Foundation
import XCTest
@testable import SpaceWorks

private final class TransferStub: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, [String: String], [Data]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
            let (status, headers, chunks) = try XCTUnwrap(handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            chunks.forEach { client?.urlProtocol(self, didLoad: $0) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class NativeFileTransferTests: XCTestCase {
    private let url = URL(string: "https://storage.example/evidence?signature=private")!
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private func transfer(_ handler: @escaping (URLRequest) throws -> (Int, [String: String], [Data])) -> NativeFileTransfer {
        TransferStub.lock.lock(); TransferStub.handler = handler; TransferStub.lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferStub.self]
        // Deliberately dirty source configuration must not leak into the storage session.
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer app-token", "Cookie": "session=web", "X-Makerspace-Id": "9"]
        return NativeFileTransfer(configuration: configuration)
    }
    override func tearDown() {
        TransferStub.lock.lock(); TransferStub.handler = nil; TransferStub.lock.unlock()
    }
    private func assertNoAppHeaders(_ request: URLRequest) {
        for name in ["Authorization", "Cookie", "Origin", "Referer", "X-Makerspace-Id"] {
            XCTAssertNil(request.value(forHTTPHeaderField: name), name)
        }
    }

    func testMultipartPreservesEverySignedFieldAndPlacesPhotoLastWithoutAppCredentials() async throws {
        let client = transfer { request in
            self.assertNoAppHeaders(request)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(String(data: requestBody(request), encoding: .isoLatin1))
            XCTAssertTrue(body.contains("name=\"key\"\r\n\r\nfolder/photo.jpg\r\n"))
            XCTAssertTrue(body.contains("name=\"policy\"\r\n\r\nsigned-policy\r\n"))
            XCTAssertTrue(body.contains("name=\"x-amz-signature\"\r\n\r\nsigned-value\r\n"))
            let photo = try XCTUnwrap(body.range(of: "name=\"file\";"))
            for key in ["key", "policy", "x-amz-signature"] {
                XCTAssertLessThan(try XCTUnwrap(body.range(of: "name=\"\(key)\"" )).lowerBound, photo.lowerBound)
            }
            XCTAssertFalse(body.contains("filename=\"../../"))
            return (204, [:], [])
        }
        try await client.uploadPOST(to: url, fields: ["key": "folder/photo.jpg", "policy": "signed-policy", "x-amz-signature": "signed-value"],
                                    photo: jpeg, contentType: "image/jpeg", filename: "../../evidence.jpg")
    }

    func testExplicitPUTSendsRawImageAndReturnedStorageHeadersOnly() async throws {
        let client = transfer { request in
            self.assertNoAppHeaders(request)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(requestBody(request), self.jpeg)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-meta-object"), "server-value")
            return (200, [:], [])
        }
        try await client.uploadPUT(to: url, headers: ["x-amz-meta-object": "server-value", "Content-Type": "image/jpeg"],
                                   photo: jpeg, contentType: "image/jpeg")
    }

    func testRejectsCredentialAndHeaderInjectionBeforeOpeningStorageConnection() async throws {
        let client = transfer { _ in XCTFail("Unsafe input must not open a connection"); return (200, [:], []) }
        for headers in [["Authorization": "Bearer leak"], ["Cookie": "session=leak"], ["X-Makerspace-Id": "3"],
                        ["X-Test": "a\r\nAuthorization: secret"], ["Content-Type": "text/html"]] {
            do {
                try await client.uploadPUT(to: url, headers: headers, photo: jpeg, contentType: "image/jpeg")
                XCTFail("Unsafe headers accepted")
            } catch { XCTAssertEqual(error as? NativeTransferError, .invalidInput) }
        }
        do {
            try await client.uploadPOST(to: url, fields: ["file": "shadow-photo"], photo: jpeg, contentType: "image/jpeg", filename: "photo")
            XCTFail("Duplicate file field accepted")
        } catch { XCTAssertEqual(error as? NativeTransferError, .invalidInput) }
    }

    func testRejectsUnsafeURLAndOversizedPhotoBeforeOpeningConnection() async throws {
        let client = transfer { _ in XCTFail("Unsafe input must not open a connection"); return (200, [:], []) }
        for address in ["http://storage.example/photo", "https://user:password@storage.example/photo", "https://storage.example/photo#fragment", "file:///private/photo"] {
            do {
                try await client.uploadPUT(to: URL(string: address)!, headers: [:], photo: jpeg, contentType: "image/jpeg")
                XCTFail("Unsafe URL accepted")
            } catch { XCTAssertEqual(error as? NativeTransferError, .invalidURL) }
        }
        do {
            try await client.uploadPUT(to: url, headers: [:], photo: jpeg, contentType: "image/jpeg", maximumBytes: 3)
            XCTFail("Oversized photo accepted")
        } catch { XCTAssertEqual(error as? NativeTransferError, .tooLarge) }
    }

    func testDownloadCreatesProtectedLocalPDFAndDeletesItAfterPresentationOwnerReleases() async throws {
        let bytes = Data("%PDF-1.7\nfixture".utf8)
        let client = transfer { request in
            self.assertNoAppHeaders(request)
            XCTAssertEqual(request.httpMethod, "GET")
            return (200, ["Content-Type": "application/pdf"], [bytes])
        }
        var file: NativeDocumentFile? = try await client.download(from: url, kind: .pdf, suggestedName: "../../Receipt<script>")
        let localURL = try XCTUnwrap(file?.url)
        XCTAssertEqual(localURL.pathExtension, "pdf")
        XCTAssertEqual(try Data(contentsOf: localURL), bytes)
        XCTAssertEqual(localURL.deletingLastPathComponent().resolvingSymlinksInPath(), FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
        file = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
    }

    func testDownloadRejectsOversizedDeclaredOrChunkedResponseAndHTMLMasqueradingAsPDF() async throws {
        let responses: [(Int, [String: String], [Data], NativeTransferError)] = [
            (200, ["Content-Type": "application/pdf", "Content-Length": "9999"], [], .tooLarge),
            (200, ["Content-Type": "application/pdf"], [Data("%PDF-".utf8), Data(repeating: 0, count: 30)], .tooLarge),
            (200, ["Content-Type": "text/html"], [Data("%PDF-fake".utf8)], .unsupportedDocument),
            (200, ["Content-Type": "application/pdf"], [Data("<html>not a document</html>".utf8)], .unsupportedDocument),
            (403, ["Content-Type": "text/html"], [Data("private signed URL error".utf8)], .refused)
        ]
        for (status, headers, chunks, expected) in responses {
            let client = transfer { _ in (status, headers, chunks) }
            do {
                _ = try await client.download(from: url, kind: .pdf, suggestedName: "receipt", maximumBytes: 32)
                XCTFail("Unsafe response accepted")
            } catch { XCTAssertEqual(error as? NativeTransferError, expected) }
        }
    }

    func testCancellationBeforeStartDoesNotCreateStorageRequest() async throws {
        let client = transfer { _ in XCTFail("Cancelled task must not connect"); return (200, [:], []) }
        let operation = NativeTransferOperation(configuration: .ephemeral, limit: 32, accepts: { _ in true })
        operation.cancel()
        do { _ = try await operation.perform(URLRequest(url: url)); XCTFail("Cancelled operation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = client // Retain the stub throughout the cancellation test.
    }

    func testRedirectDelegateRejectsTheNewRequestWithoutForwardingCredentials() {
        let operation = NativeTransferOperation(configuration: .ephemeral, limit: 32, accepts: { _ in true })
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        operation.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                             newRequest: URLRequest(url: URL(string: "https://unexpected.example")!)) { next in
            XCTAssertNil(next)
        }
    }
}
