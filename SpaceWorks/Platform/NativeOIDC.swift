import CryptoKit
import Foundation
import SpaceWorksAPI
import UIKit

/// Organization OIDC through the provider's own public client: authorization code with PKCE in an
/// ephemeral system browser (RFC 8252). Discovery and the code exchange go only to the identity
/// provider issuer the server publishes, never to the Space Works API, and carry no app credentials.
/// The resulting ID token is then exchanged for a device grant through the generated social operation.
struct NativeOIDCClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)
    struct Endpoints: Equatable, Sendable { let authorization: URL; let token: URL }
    struct Authorization: Equatable, Sendable { let url: URL; let state: String; let verifier: String }
    let fetch: Fetch

    static let live = NativeOIDCClient { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The configured provider slug, from the published `oidc:{slug}` key.
    static func slug(fromKey key: String) -> String? {
        guard key.hasPrefix("oidc:") else { return nil }
        let slug = String(key.dropFirst("oidc:".count))
        return slug.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) == nil ? nil : slug
    }

    static func secureURL(_ value: String) -> URL? {
        guard let parts = URLComponents(string: value), parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil, let url = parts.url else { return nil }
        return url
    }

    func discover(issuer: String) async throws -> Endpoints {
        guard Self.secureURL(issuer) != nil, URLComponents(string: issuer)?.query == nil,
              let url = URL(string: (issuer.hasSuffix("/") ? String(issuer.dropLast()) : issuer) + "/.well-known/openid-configuration") else {
            throw NativeIdentity.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await fetch(request)
        guard status == 200, let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["issuer"] as? String == issuer,
              let authorization = (document["authorization_endpoint"] as? String).flatMap(Self.secureURL),
              let token = (document["token_endpoint"] as? String).flatMap(Self.secureURL) else { throw NativeIdentity.unavailable }
        return Endpoints(authorization: authorization, token: token)
    }

    static func authorization(_ endpoints: Endpoints, clientID: String, nonce: String,
                              random: (Int) -> Data = NativeOIDCClient.randomBytes) -> Authorization? {
        guard !clientID.isEmpty, !nonce.isEmpty, var parts = URLComponents(url: endpoints.authorization, resolvingAgainstBaseURL: false) else { return nil }
        let state = base64URL(random(16))
        let verifier = base64URL(random(32))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        parts.queryItems = (parts.queryItems ?? []) + [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: NativeOIDCBrowser.redirectURI), .init(name: "scope", value: "openid email profile"),
            .init(name: "state", value: state), .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        guard let url = parts.url else { return nil }
        return Authorization(url: url, state: state, verifier: verifier)
    }

    func exchange(_ endpoints: Endpoints, clientID: String, code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: endpoints.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form(["grant_type": "authorization_code", "code": code, "redirect_uri": NativeOIDCBrowser.redirectURI,
                                      "client_id": clientID, "code_verifier": verifier])
        let (data, status) = try await fetch(request)
        guard status == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["id_token"] as? String, !token.isEmpty else { throw NativeIdentity.unavailable }
        return token
    }

    static func form(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let body = values.keys.sorted().map { key in
            key + "=" + (values[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
        return Data(body.utf8)
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    /// The system generator is cryptographically secure on Apple platforms.
    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// Discovery, browser authorization and the PKCE code exchange for one configured organization provider.
@MainActor final class NativeOIDCSignIn {
    private let browser = NativeOIDCBrowser()
    private let client: NativeOIDCClient
    init(client: NativeOIDCClient = .live) { self.client = client }
    func credential(issuer: String, clientID: String, nonce: String, anchor: UIWindow) async throws -> ProviderCredential {
        let endpoints = try await client.discover(issuer: issuer)
        guard let request = NativeOIDCClient.authorization(endpoints, clientID: clientID, nonce: nonce) else { throw NativeIdentity.unavailable }
        let code = try await browser.authorize(url: request.url, expectedState: request.state, anchor: anchor)
        return ProviderCredential(idToken: try await client.exchange(endpoints, clientID: clientID, code: code, verifier: request.verifier))
    }
}
