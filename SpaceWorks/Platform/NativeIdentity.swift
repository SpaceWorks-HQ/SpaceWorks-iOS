import AuthenticationServices
import GoogleSignIn
import SpaceWorksAPI
import UIKit

/// Provider SDK seams. Live buttons remain gated until the server publishes native client configuration.
@MainActor enum NativeIdentity {
    static func google(clientID: String, serverClientID: String?, nonce: String, presenting: UIViewController) async throws -> String {
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !nonce.isEmpty else { throw unavailable }
        let prefix = String(clientID.dropLast(".apps.googleusercontent.com".count))
        let reversed = "com.googleusercontent.apps.\(prefix)"
        let registrations = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard registrations.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversed) == true }) else { throw unavailable }
        let provider = GIDSignIn.sharedInstance
        provider.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        // The app owns the device grant. Avoid retaining an independent Google account session.
        defer { provider.signOut() }
        let result = try await provider.signIn(withPresenting: presenting, hint: nil, additionalScopes: nil, nonce: nonce)
        try Task.checkCancellation()
        guard let token = result.user.idToken?.tokenString, !token.isEmpty else { throw unavailable }
        return token
    }
    static func handleGoogleCallback(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
    nonisolated static var unavailable: APIError {
        APIError(status: 0, code: "native_provider_unconfigured", detail: String(localized: "Native sign-in is not configured for this build. Contact your makerspace."))
    }
}

@MainActor final class AppleIdentity: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?
    private var anchor: ASPresentationAnchor?
    private var controller: ASAuthorizationController?
    func token(nonce: String, anchor: ASPresentationAnchor) async throws -> String {
        guard !nonce.isEmpty, continuation == nil else { throw NativeIdentity.unavailable }
        self.anchor = anchor
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            // Match the server-issued nonce contract also consumed by the existing frontend.
            request.nonce = nonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor! }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            finish(.failure(NativeIdentity.unavailable)); return
        }
        finish(.success(token))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<String, Error>) {
        let pending = continuation; continuation = nil; controller = nil; anchor = nil
        pending?.resume(with: result)
    }
}

/// ASWebAuthenticationSession is the sole browser-auth surface. The backend native OIDC callback is deferred.
@MainActor final class NativeOIDCBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    func authorize(url: URL, expectedState: String, anchor: ASPresentationAnchor) async throws -> String {
        guard url.scheme == "https", url.user == nil, url.password == nil, !expectedState.isEmpty, session == nil else { throw NativeIdentity.unavailable }
        self.anchor = anchor
        defer { session = nil; self.anchor = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "spaceworks") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: NativeIdentity.unavailable) }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: NativeIdentity.unavailable) }
        }
        try Task.checkCancellation()
        guard callback.scheme == "spaceworks", callback.host == "auth", callback.path == "/callback",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "state" }).count == 1,
              parts.queryItems?.filter({ $0.name == "code" }).count == 1, parts.fragment == nil,
              parts.queryItems?.first(where: { $0.name == "state" })?.value == expectedState,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw NativeIdentity.unavailable }
        return code
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor! }
}
