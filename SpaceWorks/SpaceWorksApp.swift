import SwiftUI
import SpaceWorksAPI

@main
struct SpaceWorksApp: App {
    init() {
        NativeAppearance.apply()
        if let saved = Brand.serverURL ?? UserDefaults.standard.string(forKey: "server-origin"),
           let origin = try? ServerOrigin(saved), (try? TokenVault(origin: origin).load()) != nil {
            // Upgrade an existing signed-in installation without inserting a tour into restoration.
            UserDefaults.standard.set(true, forKey: "introduction-complete")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            UserDefaults.standard.removeObject(forKey: "server-origin")
            UserDefaults.standard.removeObject(forKey: "dark-mode")
            UserDefaults.standard.removeObject(forKey: "makerspace-selection")
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("makerspace-selection.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if ProcessInfo.processInfo.arguments.contains("--reset-introduction") {
                UserDefaults.standard.set(false, forKey: "introduction-complete")
            } else if !ProcessInfo.processInfo.arguments.contains("--introduction") {
                UserDefaults.standard.set(true, forKey: "introduction-complete")
            }
            if let origin = try? ServerOrigin("https://ui-test.spaceworks.invalid") { try? TokenVault(origin: origin).store(nil) }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum DeploymentHealth {
    static func check(_ origin: ServerOrigin) async throws {
        let session = DeploymentSession.make()
        defer { session.finishTasksAndInvalidate() }
        try await SpaceWorksService(origin: origin, session: session).health()
    }
}

enum DeploymentSession {
    static func make() -> URLSession {
        let config = DeviceSession.configuration()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            config.protocolClasses = [PreviewHealthProtocol.self]
        }
        #endif
        return DeviceSession.make(configuration: config)
    }
}

#if DEBUG
/// A deterministic URLProtocol fake used only by UI automation. Production never includes it.
final class PreviewHealthProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") && request.url?.host == "ui-test.spaceworks.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let arguments = ProcessInfo.processInfo.arguments
        let path = "/" + request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let failure = arguments.contains("--health-unavailable") && path == "/api/v1/health"
        let code = failure ? 503 : 200
        let body: String
        if failure { body = #"{"detail":"Try again later.","code":"service_unavailable"}"# }
        else {
            switch path {
            case "/api/v1/config": body = DebugAuthFixtures.config
            case "/api/v1/auth/device/attestation-challenge": body = #"{"challenge":"fresh-test-challenge","expires_in":120}"#
            case "/api/v1/auth/device/login": body = arguments.contains("--mfa") ? DebugAuthFixtures.mfa : DebugAuthFixtures.tokens
            case "/api/v1/auth/me": body = DebugAuthFixtures.user
            case "/api/v1/auth/mfa/verify": body = "{\"access\":\"test-access\",\"refresh\":\"test-refresh\",\"device_grant\":\(DebugAuthFixtures.grant),\"surface\":\"member\",\"user\":\(DebugAuthFixtures.user)}"
            case "/api/v1/auth/device/logout": body = #"{"detail":"Signed out."}"#
            case "/api/v1/auth/member-sign-up", "/api/v1/auth/forgot-password", "/api/v1/auth/reset-password",
                 "/api/v1/auth/email-verification/confirm", "/api/v1/auth/email-verification/resend": body = #"{"detail":"Check your email."}"#
            default: body = #"{"status":"ok"}"#
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
