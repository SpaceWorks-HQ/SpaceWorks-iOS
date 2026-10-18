import CryptoKit
import XCTest
import UIKit
@testable import SpaceWorks

private final class OIDCRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); values.append(request); lock.unlock() }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return values }
}

@MainActor final class NativeIdentityTests: XCTestCase {
    func testGoogleWithoutRegisteredBuildConfigurationFailsBeforeSDKLaunch() async {
        do {
            _ = try await NativeIdentity.google(clientID: "", nonce: "sample", presenting: UIViewController())
            XCTFail("Unconfigured provider must fail before presentation")
        } catch { XCTAssertEqual(error.localizedDescription, NativeIdentity.unavailable.localizedDescription) }
    }
    func testOIDCProviderKeyYieldsOnlyAValidConfiguredSlug() {
        XCTAssertEqual(NativeOIDCClient.slug(fromKey: "oidc:campus-sso"), "campus-sso")
        XCTAssertNil(NativeOIDCClient.slug(fromKey: "google"))
        XCTAssertNil(NativeOIDCClient.slug(fromKey: "oidc:../admin"))
        XCTAssertNil(NativeOIDCClient.slug(fromKey: "oidc:"))
    }
    func testOIDCDiscoveryRequiresTheExactIssuerAndSecureEndpoints() async throws {
        let issuer = "https://id.example.test/realms/makers"
        func client(_ document: String, status: Int = 200) -> NativeOIDCClient {
            NativeOIDCClient { request in
                XCTAssertEqual(request.url?.absoluteString, issuer + "/.well-known/openid-configuration")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (Data(document.utf8), status)
            }
        }
        let valid = #"{"issuer":"https://id.example.test/realms/makers","authorization_endpoint":"https://id.example.test/auth","token_endpoint":"https://id.example.test/token"}"#
        let endpoints = try await client(valid).discover(issuer: issuer)
        XCTAssertEqual(endpoints.token.absoluteString, "https://id.example.test/token")
        for document in [valid.replacingOccurrences(of: "realms/makers\"", with: "realms/other\""),
                         valid.replacingOccurrences(of: "https://id.example.test/token", with: "http://id.example.test/token")] {
            do { _ = try await client(document).discover(issuer: issuer); XCTFail("Mismatched or insecure discovery must be refused") }
            catch { XCTAssertEqual(APIError.code(error), "native_provider_unconfigured") }
        }
        do { _ = try await client(valid).discover(issuer: "http://id.example.test"); XCTFail("Insecure issuer must be refused before any request") }
        catch { XCTAssertEqual(APIError.code(error), "native_provider_unconfigured") }
    }
    func testOIDCAuthorizationUsesPKCEStateAndTheServerNonce() throws {
        let endpoints = NativeOIDCClient.Endpoints(authorization: URL(string: "https://id.example.test/auth?kc_idp_hint=campus")!, token: URL(string: "https://id.example.test/token")!)
        let request = try XCTUnwrap(NativeOIDCClient.authorization(endpoints, clientID: "makers-app", nonce: "server-nonce") { Data(repeating: 7, count: $0) })
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["kc_idp_hint"], "campus", "Existing provider parameters are preserved")
        XCTAssertEqual(items["response_type"], "code"); XCTAssertEqual(items["client_id"], "makers-app")
        XCTAssertEqual(items["redirect_uri"], "spaceworks://auth/callback"); XCTAssertEqual(items["nonce"], "server-nonce")
        XCTAssertEqual(items["state"], request.state); XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], NativeOIDCClient.base64URL(Data(SHA256.hash(data: Data(request.verifier.utf8)))))
        XCTAssertFalse(request.verifier.contains("=") || request.verifier.contains("+") || request.verifier.contains("/"))
    }
    func testOIDCCodeExchangePostsTheVerifierAndReturnsOnlyTheIDToken() async throws {
        let seen = OIDCRequests()
        let client = NativeOIDCClient { request in
            seen.append(request)
            return (Data(#"{"access_token":"provider-access","id_token":"provider-id-token","token_type":"Bearer"}"#.utf8), 200)
        }
        let endpoints = NativeOIDCClient.Endpoints(authorization: URL(string: "https://id.example.test/auth")!, token: URL(string: "https://id.example.test/token")!)
        let token = try await client.exchange(endpoints, clientID: "makers app", code: "abc/123", verifier: "verifier-value")
        XCTAssertEqual(token, "provider-id-token")
        let request = try XCTUnwrap(seen.all.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(String(decoding: request.httpBody ?? Data(), as: UTF8.self),
                       "client_id=makers%20app&code=abc%2F123&code_verifier=verifier-value&grant_type=authorization_code&redirect_uri=spaceworks%3A%2F%2Fauth%2Fcallback")
    }
    func testOrganizationBrowserRejectsInsecureURLBeforePresentation() async {
        let browser = NativeOIDCBrowser()
        do {
            _ = try await browser.authorize(url: URL(string: "http://identity.example/authorize")!, expectedState: "sample", anchor: UIWindow(frame: .zero))
            XCTFail("Insecure identity provider must fail before presentation")
        } catch { XCTAssertEqual(error.localizedDescription, NativeIdentity.unavailable.localizedDescription) }
    }
}
