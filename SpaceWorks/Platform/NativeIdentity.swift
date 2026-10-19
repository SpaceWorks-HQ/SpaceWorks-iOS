import AuthenticationServices
import CryptoKit
import GoogleSignIn
import SpaceWorksAPI
import UIKit

/// The provider result handed to the generated social sign-in operation. Tokens are never logged or persisted.
struct ProviderCredential: Sendable {
    let idToken: String
    var authorizationCode: String? = nil
    var appleName: String? = nil
}

/// Provider SDK seams. Buttons render only for providers the server publishes in `PublicConfig.native`.
@MainActor enum NativeIdentity {
    static func google(clientID: String, nonce: String, presenting: UIViewController) async throws -> ProviderCredential {
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !nonce.isEmpty else { throw unavailable }
        let prefix = String(clientID.dropLast(".apps.googleusercontent.com".count))
        let reversed = "com.googleusercontent.apps.\(prefix)"
        let registrations = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard registrations.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversed) == true }) else { throw unavailable }
        let provider = GIDSignIn.sharedInstance
        // The server verifies the iOS client ID as the token audience, so no server client ID is set.
        provider.configuration = GIDConfiguration(clientID: clientID)
        // The app owns the device grant. Avoid retaining an independent Google account session.
        defer { provider.signOut() }
        do {
            let result = try await provider.signIn(withPresenting: presenting, hint: nil, additionalScopes: nil, nonce: nonce)
            try Task.checkCancellation()
            guard let token = result.user.idToken?.tokenString, !token.isEmpty else { throw unavailable }
            return ProviderCredential(idToken: token)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw CancellationError()
        }
    }
    static func handleGoogleCallback(_ url: URL) -> Bool { GIDSignIn.sharedInstance.handle(url) }
    nonisolated static var unavailable: APIError {
        APIError(status: 0, code: "native_provider_unconfigured", detail: String(localized: "Native sign-in is not configured for this build. Contact your makerspace."))
    }
}

/// The foreground scene's key window and its top presented controller.
@MainActor enum NativePresentation {
    static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
    }
    static var topController: UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

@MainActor final class AppleIdentity: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ProviderCredential, Error>?
    private var anchor: ASPresentationAnchor?
    private var controller: ASAuthorizationController?
    func credential(nonce: String, anchor: ASPresentationAnchor) async throws -> ProviderCredential {
        guard !nonce.isEmpty, continuation == nil else { throw NativeIdentity.unavailable }
        self.anchor = anchor
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            // The server accepts the issued nonce verbatim (or its SHA-256) in the identity token.
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
        // Apple shares the name only on first authorization; the code lets the server revoke on deletion.
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(.success(ProviderCredential(idToken: token, authorizationCode: code?.isEmpty == false ? code : nil,
                                           appleName: name?.isEmpty == false ? String(name!.prefix(200)) : nil)))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { finish(.failure(CancellationError())) }
        else { finish(.failure(error)) }
    }
    private func finish(_ result: Result<ProviderCredential, Error>) {
        let pending = continuation; continuation = nil; controller = nil; anchor = nil
        pending?.resume(with: result)
    }
}

/// ASWebAuthenticationSession is the sole browser surface: an ephemeral system session, no web cookies.
@MainActor final class NativeOIDCBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "spaceworks://auth/callback"
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    func authorize(url: URL, expectedState: String, anchor: ASPresentationAnchor) async throws -> String {
        guard url.scheme == "https", url.user == nil, url.password == nil, !expectedState.isEmpty, session == nil else { throw NativeIdentity.unavailable }
        self.anchor = anchor
        defer { session = nil; self.anchor = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "spaceworks") { callback, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? CancellationError() : error)
                }
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
