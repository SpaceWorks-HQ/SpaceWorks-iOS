import Foundation

enum NativeTransferError: LocalizedError, Equatable {
    case invalidURL, invalidInput, tooLarge, refused, unsupportedDocument, failed
    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "This file link is unavailable. Request a new link and try again.")
        case .invalidInput: return String(localized: "This file could not be prepared. Choose another file and try again.")
        case .tooLarge: return String(localized: "This file exceeds the supported size. Try a smaller file or use the web console.")
        case .refused: return String(localized: "File access was refused. Request a new link and try again.")
        case .unsupportedDocument: return String(localized: "This document could not be opened in the app.")
        case .failed: return String(localized: "Couldn't transfer this file. Check your connection and try again.")
        }
    }
}

/// Local presentation metadata, not an API model. The owner must retain this while previewing/sharing.
final class NativeDocumentFile: Identifiable {
    let id = UUID()
    let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

enum NativeDocumentKind {
    case pdf, jpeg, png, zip
    var fileExtension: String {
        switch self { case .pdf: return "pdf"; case .jpeg: return "jpg"; case .png: return "png"; case .zip: return "zip" }
    }
    func accepts(_ mime: String) -> Bool {
        switch self {
        case .pdf: return mime == "application/pdf"
        case .jpeg: return mime == "image/jpeg"
        case .png: return mime == "image/png"
        case .zip: return ["application/zip", "application/x-zip-compressed", "application/octet-stream"].contains(mime)
        }
    }
    func recognizes(_ data: Data) -> Bool {
        switch self {
        case .pdf: return data.starts(with: Data("%PDF-".utf8))
        case .jpeg: return data.starts(with: [0xFF, 0xD8, 0xFF])
        case .png: return data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        case .zip: return [[80, 75, 3, 4], [80, 75, 5, 6], [80, 75, 7, 8]].contains { data.starts(with: $0.map(UInt8.init)) }
        }
    }
}

/// Only for URLs/fields returned by supported generated API operations after authorization.
/// API requests themselves stay in the generated gateway. Never pass an app access token here.
struct NativeFileTransfer {
    private let configuration: URLSessionConfiguration
    private let debugHTTPOrigin: URL?
    private static let hardLimit = 100 * 1024 * 1024

    init(configuration: URLSessionConfiguration = .ephemeral, debugHTTPOrigin: URL? = nil) {
        let isolated = configuration.copy() as! URLSessionConfiguration
        isolated.httpCookieStorage = nil
        isolated.urlCredentialStorage = nil
        isolated.httpShouldSetCookies = false
        isolated.httpAdditionalHeaders = nil
        isolated.urlCache = nil
        isolated.requestCachePolicy = .reloadIgnoringLocalCacheData
        isolated.timeoutIntervalForRequest = 30
        isolated.timeoutIntervalForResource = 120
        self.configuration = isolated
        self.debugHTTPOrigin = debugHTTPOrigin
    }

    func download(from url: URL, kind: NativeDocumentKind, suggestedName: String,
                  maximumBytes: Int = 25 * 1024 * 1024) async throws -> NativeDocumentFile {
        try validate(url)
        try validateLimit(maximumBytes)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await transfer(request, limit: maximumBytes, accepts: { kind.accepts($0.mimeType ?? "") })
        return try Self.document(data: data, kind: kind, suggestedName: suggestedName, maximumBytes: maximumBytes)
    }

    /// Use for bytes returned by a generated authenticated binary operation; no second network fetch.
    static func document(data: Data, kind: NativeDocumentKind, suggestedName: String,
                         maximumBytes: Int = 25 * 1024 * 1024) throws -> NativeDocumentFile {
        guard maximumBytes > 0, maximumBytes <= Self.hardLimit else { throw NativeTransferError.invalidInput }
        guard data.count <= maximumBytes else { throw NativeTransferError.tooLarge }
        guard kind.recognizes(data) else { throw NativeTransferError.unsupportedDocument }
        try Task.checkCancellation()
        let safeName = Self.filename(suggestedName)
        // The UUID prevents path collisions; the extension comes from the expected document kind.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + "-" + safeName + "." + kind.fileExtension)
        do { try data.write(to: file, options: [.atomic, .completeFileProtection]) }
        catch { throw NativeTransferError.failed }
        return NativeDocumentFile(url: file)
    }

    /// Missing presign method means multipart POST. Send every returned field, then the file last.
    func uploadPOST(to url: URL, fields: [String: String], photo: Data, contentType: String,
                    filename: String, maximumBytes: Int = 20 * 1024 * 1024) async throws {
        try validate(url)
        try validatePhoto(photo, contentType: contentType, maximumBytes: maximumBytes)
        guard fields.count <= 64, fields.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) <= 512 * 1024,
              fields.allSatisfy({ key, value in
                  !key.isEmpty && key.utf8.count <= 128 && key != "file" &&
                  key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }) &&
                  value.utf8.count <= 64 * 1024
              }) else { throw NativeTransferError.invalidInput }
        let boundary = "SpaceWorks-" + UUID().uuidString
        var body = Data()
        for key in fields.keys.sorted() {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n".utf8))
        }
        let name = Self.filename(filename)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(photo)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await transfer(request, limit: 64 * 1024)
    }

    /// Use only when the generated presign response explicitly selects PUT.
    func uploadPUT(to url: URL, headers: [String: String], photo: Data, contentType: String,
                   maximumBytes: Int = 20 * 1024 * 1024) async throws {
        try validate(url)
        try validatePhoto(photo, contentType: contentType, maximumBytes: maximumBytes)
        let forbidden: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie", "origin", "referer",
            "x-makerspace-id", "host", "content-length", "transfer-encoding", "connection", "keep-alive", "te", "trailer", "upgrade"]
        guard headers.count <= 64, headers.allSatisfy({ key, value in
            !forbidden.contains(key.lowercased()) && !key.isEmpty && key.utf8.count <= 128 && value.utf8.count <= 8192 &&
            key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) && !"()<>@,;:\\\"/[]?={} ".unicodeScalars.contains($0) }) &&
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
            (key.lowercased() != "content-type" || value == contentType)
        }) else { throw NativeTransferError.invalidInput }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = photo
        _ = try await transfer(request, limit: 64 * 1024)
    }

    private func validate(_ url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw NativeTransferError.invalidURL
        }
        if parts.scheme == "https" { return }
        #if DEBUG
        if parts.scheme == "http", ["localhost", "127.0.0.1", "[::1]", "::1"].contains(parts.host?.lowercased() ?? ""),
           let origin = debugHTTPOrigin, origin.scheme == "http", origin.host == url.host, origin.port == url.port,
           origin.user == nil, origin.password == nil, origin.path.isEmpty || origin.path == "/",
           origin.query == nil, origin.fragment == nil { return }
        #endif
        throw NativeTransferError.invalidURL
    }

    private func validateLimit(_ limit: Int) throws {
        guard limit > 0, limit <= Self.hardLimit else { throw NativeTransferError.invalidInput }
    }
    private func validatePhoto(_ data: Data, contentType: String, maximumBytes: Int) throws {
        try validateLimit(maximumBytes)
        guard data.count <= maximumBytes else { throw NativeTransferError.tooLarge }
        let kind: NativeDocumentKind
        switch contentType { case "image/jpeg": kind = .jpeg; case "image/png": kind = .png; default: throw NativeTransferError.invalidInput }
        guard kind.recognizes(data) else { throw NativeTransferError.invalidInput }
    }
    private static func filename(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || "-_".unicodeScalars.contains($0)
        }.prefix(80)
        let result = String(String.UnicodeScalarView(scalars))
        return result.isEmpty ? "document" : result
    }
    private func transfer(_ request: URLRequest, limit: Int,
                          accepts: @escaping (HTTPURLResponse) -> Bool = { _ in true }) async throws -> Data {
        let operation = NativeTransferOperation(configuration: configuration, limit: limit, accepts: accepts)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await operation.perform(request)
        } onCancel: { operation.cancel() }
    }
}

/// Each transfer owns a separate cookie-free session and bounded response buffer. State is lock-confined.
final class NativeTransferOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let limit: Int
    private let accepts: (HTTPURLResponse) -> Bool
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var cancelled = false
    private var buffer = Data()
    init(configuration: URLSessionConfiguration, limit: Int, accepts: @escaping (HTTPURLResponse) -> Bool) {
        self.configuration = configuration; self.limit = limit; self.accepts = accepts
    }
    func perform(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            lock.unlock()
            task.resume()
        }
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            completionHandler(.cancel); finish(.failure(NativeTransferError.refused)); return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(NativeTransferError.tooLarge)); return
        }
        guard accepts(response) else {
            completionHandler(.cancel); finish(.failure(NativeTransferError.unsupportedDocument)); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        if data.count > limit - buffer.count {
            lock.unlock(); finish(.failure(NativeTransferError.tooLarge)); return
        }
        buffer.append(data)
        lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = buffer; let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { finish(.failure(CancellationError())) }
        else if error != nil { finish(.failure(NativeTransferError.failed)) }
        else { finish(.success(data)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(NativeTransferError.refused))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Use normal system TLS trust. Never consult a shared credential store for an HTTP challenge.
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
