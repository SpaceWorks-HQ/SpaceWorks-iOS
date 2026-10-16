import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// A deployment origin, never an API path or a URL with embedded credentials.
public struct ServerOrigin: Sendable, Equatable {
    public let url: URL
    public init(_ input: String, allowLocalHTTP: Bool = false) throws {
        #if DEBUG
        let localHTTP = allowLocalHTTP
        #else
        let localHTTP = false
        #endif
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, ["", "/"].contains(parts.path),
              parts.port == nil || (1...65535).contains(parts.port!),
              parts.scheme == "https" || (localHTTP && parts.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        else { throw APIError(status: 0, code: "invalid_server_url", detail: "Enter a valid HTTPS server URL.") }
        parts.path = ""
        guard let url = parts.url else { throw URLError(.badURL) }
        self.url = url
    }

    /// Pagination must retain the deployment origin and API namespace before any auth is sent.
    public func nextPage(_ next: String?) throws -> URL? {
        guard let next else { return nil }
        guard let candidate = URL(string: next, relativeTo: url)?.absoluteURL,
              let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: true),
              candidate.scheme == url.scheme, candidate.host == url.host,
              (candidate.port ?? (candidate.scheme == "https" ? 443 : 80)) == (url.port ?? (url.scheme == "https" ? 443 : 80)),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              candidate.path.hasPrefix("/api/"),
              !(parts.percentEncodedPath.removingPercentEncoding ?? "").split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { throw APIError(status: 0, code: "invalid_next_page", detail: "The server returned an invalid next page.") }
        return candidate
    }
}

public struct APIError: Error, LocalizedError, Sendable, Equatable {
    public let status: Int
    public let code: String
    public let detail: String
    public let retryAfter: Date?
    public init(status: Int, code: String, detail: String, retryAfter: Date? = nil) {
        self.status = status; self.code = code; self.detail = detail; self.retryAfter = retryAfter
    }
    public var errorDescription: String? {
        switch code {
        case "device_superadmin_not_supported": return "Use the web console"
        case "payment_rail_conflict": return "Finish this payment on the web."
        case "payments_unavailable": return "Online payment is unavailable. Try again later or pay at the desk."
        default: return detail
        }
    }

    public static func display(_ error: Error) -> String {
        if let error = error as? APIError { return error.errorDescription ?? error.detail }
        if let error = error as? ClientError { return display(error.underlyingError) }
        return "Couldn't connect. Try again."
    }
    public static func retryDeadline(_ error: Error) -> Date? {
        if let error = error as? APIError { return error.retryAfter }
        if let error = error as? ClientError { return retryDeadline(error.underlyingError) }
        return nil
    }
}

/// Local credentials, not a hand-written API payload. Persist together in Keychain in A1.
public struct TokenPair: Sendable, Equatable {
    public let access: String
    public let refresh: String
    public init(access: String, refresh: String) { self.access = access; self.refresh = refresh }
}

/// One actor owns the pair and the in-flight task. Late 401s from the old generation reuse the new pair.
public actor RefreshCoordinator {
    private var pair: TokenPair?
    private var flight: Task<TokenPair, Error>?
    private let rotate: @Sendable (String) async throws -> TokenPair
    public init(pair: TokenPair? = nil, rotate: @escaping @Sendable (String) async throws -> TokenPair) {
        self.pair = pair; self.rotate = rotate
    }
    public func current() -> TokenPair? { pair }
    public func recover(rejectedAccess: String) async throws -> TokenPair {
        guard let current = pair else { throw APIError(status: 401, code: "signed_out", detail: "Sign in to continue.") }
        if current.access != rejectedAccess { return current }
        if let flight { return try await flight.value }
        let rotate = self.rotate
        let task = Task {
            do {
                let updated = try await rotate(current.refresh)
                self.commit(updated)
                return updated
            } catch {
                self.commit(nil)
                throw error
            }
        }
        flight = task
        return try await task.value
    }
    private func commit(_ value: TokenPair?) {
        // Atomic pair replacement completes inside the shared task before any waiter can retry.
        pair = value
        flight = nil
    }
}

public actor MakerspaceContext {
    private var selected: Int?
    public init() {}
    public func current() -> Int? { selected }
    /// A1 supplies active membership IDs from the generated /auth/me response.
    public func select(_ id: Int?, activeMemberships: Set<Int>) throws {
        guard id == nil || activeMemberships.contains(id!) else {
            throw APIError(status: 403, code: "inactive_membership", detail: "Select an active makerspace membership.")
        }
        selected = id
    }
}

private func checked(_ result: (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
    let (response, body) = result
    guard response.status.code >= 300 else { return result }
    let data = try await body.mapAsync { try await Data(collecting: $0, upTo: 1_048_576) }
    let envelope = data.flatMap { try? JSONDecoder().decode(Components.Schemas.HardwareRequestError.self, from: $0) }
    // Framework/validation errors have intentionally variable shapes (§7); retain dynamic JSON rather than inventing API models.
    let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let code = envelope?.code ?? object?["code"] as? String
    let detail = envelope?.detail ?? object?["detail"] as? String
    let fields = object?.keys.sorted().filter { !["detail", "code"].contains($0) }.compactMap { key -> String? in
        guard let messages = object?[key] as? [String], !messages.isEmpty else { return nil }
        return "\(key): \(messages.joined(separator: " "))"
    }.joined(separator: "\n")
    var retry: Date?
    if let header = response.headerFields[.retryAfter] {
        if let seconds = TimeInterval(header) { retry = Date().addingTimeInterval(max(0, seconds)) }
        else {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(secondsFromGMT: 0)
            format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            retry = format.date(from: header)
        }
    }
    let fallback: String
    switch response.status.code {
    case 400: fallback = "Check the details and try again."
    case 401: fallback = "Please sign in again."
    case 403: fallback = "You do not have permission to do this."
    case 404: fallback = "This item wasn't found."
    case 409: fallback = "This changed. Refresh and try again."
    case 429: fallback = "Too many requests. Try again later."
    case 503: fallback = "The server is unavailable. Try again later."
    default: fallback = "Couldn't connect. Try again."
    }
    let message: String
    if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { message = detail }
    else if response.status.code == 400, let fields, !fields.isEmpty { message = fields }
    else { message = fallback }
    throw APIError(status: response.status.code, code: code ?? "http_\(response.status.code)", detail: message, retryAfter: retry)
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}

private struct ErrorMiddleware: ClientMiddleware {
    func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                   next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        try await checked(next(request, body, baseURL))
    }
}

public struct SessionMiddleware: ClientMiddleware {
    public let refresh: RefreshCoordinator
    public let makerspace: MakerspaceContext
    public init(refresh: RefreshCoordinator, makerspace: MakerspaceContext) { self.refresh = refresh; self.makerspace = makerspace }
    public func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                          next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        for name in ["Cookie", "Origin", "Referer"] { request.headerFields[HTTPField.Name(name)!] = nil }
        let pair = await refresh.current()
        request.headerFields[.authorization] = pair.map { "Bearer \($0.access)" }
        request.headerFields[HTTPField.Name("X-Makerspace-Id")!] = await makerspace.current().map(String.init)
        let result = try await next(request, body, baseURL)
        if result.0.status.code == 401, let pair {
            let updated = try await refresh.recover(rejectedAccess: pair.access)
            request.headerFields[.authorization] = "Bearer \(updated.access)"
            return try await checked(next(request, body, baseURL))
        }
        return try await checked(result)
    }
}

/// Refuse every redirect. Credentials and health checks never move to a different host or HTTP.
public final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public enum DeviceSession {
    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return config
    }
    public static func make(configuration: URLSessionConfiguration = configuration()) -> URLSession {
        URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
}

public final class SpaceWorksService: Sendable {
    private let client: Client
    public let refresh: RefreshCoordinator
    public let makerspace: MakerspaceContext
    public init(origin: ServerOrigin, session: URLSession = DeviceSession.make(), initialTokens: TokenPair? = nil,
                makerspace: MakerspaceContext = MakerspaceContext()) {
        // Buffered mode keeps URLSession's session delegate in control of redirects. Streaming
        // transport installs its own task delegate and would bypass that guarantee.
        let transport = URLSessionTransport(configuration: .init(session: session, httpBodyProcessingMode: .buffered))
        let raw = Client(serverURL: origin.url, transport: transport, middlewares: [ErrorMiddleware()])
        let coordinator = RefreshCoordinator(pair: initialTokens) { token in
            let response = try await raw.api_v1_auth_device_refresh_create(.init(body: .json(.init(refresh: token))))
            let value = try response.ok.body.json
            return TokenPair(access: value.access, refresh: value.refresh)
        }
        self.refresh = coordinator
        self.makerspace = makerspace
        self.client = Client(serverURL: origin.url, transport: transport, middlewares: [SessionMiddleware(refresh: coordinator, makerspace: makerspace)])
    }
    public func health() async throws {
        let result = try await client.api_v1_health_retrieve()
        _ = try result.ok.body.json
    }
}
