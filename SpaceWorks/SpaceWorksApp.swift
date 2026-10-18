import SwiftUI
import SpaceWorksAPI

@main
struct SpaceWorksApp: App {
    @UIApplicationDelegateAdaptor(NativeNotificationDelegate.self) private var notificationDelegate
    init() {
        NativeAppearance.apply()
        if let saved = Brand.serverURL ?? UserDefaults.standard.string(forKey: "server-origin"),
           let origin = try? ServerOrigin(saved), (try? TokenVault(origin: origin).load()) != nil {
            // Upgrade an existing signed-in installation without inserting a tour into restoration.
            UserDefaults.standard.set(true, forKey: "introduction-complete")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            PreviewMemberResponses.reset()
            UserDefaults.standard.removeObject(forKey: "server-origin")
            // The app has an explicit theme, so simulator appearance alone is insufficient.
            let appearance = ProcessInfo.processInfo.environment["SPACEWORKS_TEST_APPEARANCE"]
            UserDefaults.standard.set(appearance == "dark", forKey: "dark-mode")
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
        let superadmin = arguments.contains("--superadmin") && path == "/api/v1/auth/device/login"
        let deletion = path == "/api/v1/auth/account/deletion" && request.httpMethod == "POST"
        let code = failure ? 503 : superadmin ? 403 : deletion ? 202 : 200
        let body: String
        if failure { body = #"{"detail":"Try again later.","code":"service_unavailable"}"# }
        else if superadmin { body = #"{"detail":"Use the web console.","code":"device_superadmin_not_supported"}"# }
        else if let member = PreviewMemberResponses.response(for: request) { body = member }
        else {
            switch path {
            case "/api/v1/config":
                body = arguments.contains("--native-min-version") ? DebugAuthFixtures.nativeConfig(minimum: "99.0")
                    : arguments.contains("--native-providers") ? DebugAuthFixtures.nativeConfig() : DebugAuthFixtures.config
            case "/api/v1/auth/phone/login/start": body = #"{"detail":"If the number can sign in, a code was sent."}"#
            case "/api/v1/auth/phone/login/confirm": body = DebugAuthFixtures.tokens
            case "/api/v1/auth/logout-all": body = #"{"web_sessions":1,"devices":2}"#
            case "/api/v1/auth/account/deletion":
                body = deletion ? #"{"deleted_at":"2026-10-18T10:00:00Z","purge_after":"2027-01-16T10:00:00Z"}"#
                    : #"{"deletable":true,"restorable":true,"restore_reason":"","blockers":[],"reauth":{"required":true,"methods":["password"]}}"#
            case "/api/v1/auth/reauth":
                body = request.httpMethod == "POST" ? #"{"verified":true,"expires_in":600}"#
                    : #"{"verified":false,"password_available":true,"mfa_enabled":false,"providers":[]}"#
            case "/api/v1/bootstrap": body = DebugMemberFixtures.bootstrap
            case "/api/v1/auth/device/attestation-challenge": body = #"{"challenge":"fresh-test-challenge","expires_in":120}"#
            case "/api/v1/auth/device/login": body = arguments.contains("--mfa") ? DebugAuthFixtures.mfa : DebugAuthFixtures.tokens
            case "/api/v1/auth/me":
                body = arguments.contains("--native-staff") ? DebugAuthFixtures.staffUser
                    : arguments.contains("--temporary-password") ? DebugAuthFixtures.user.replacingOccurrences(of: "\"must_change_password\":false", with: "\"must_change_password\":true") : DebugAuthFixtures.user
            case "/api/v1/admin/makerspace/7/pending-requests":
                body = #"{"count":1,"next":null,"previous":null,"results":["# + DebugStaffFixtures.request + "]}"
            case "/api/v1/auth/mfa/verify": body = "{\"access\":\"test-access\",\"refresh\":\"test-refresh\",\"device_grant\":\(DebugAuthFixtures.grant),\"surface\":\"member\",\"user\":\(DebugAuthFixtures.user)}"
            case "/api/v1/auth/device/logout": body = #"{"detail":"Signed out."}"#
            case "/api/v1/auth/change-password": body = #"{"detail":"Password updated."}"#
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

/// Test-only server state, separated from the interactive demo and absent from Release.
private enum PreviewMemberResponses {
    static let lock = NSLock()
    static var readIDs = Set<Int>()
    static func reset() { lock.lock(); readIDs = []; lock.unlock() }
    static func response(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("inventory/categories") { return DebugMemberFixtures.categories }
        if path.contains("/inventory/") {
            return first(DebugMemberFixtures.inventory, id: Int(path.split(separator: "/").last ?? ""))
        }
        if path.hasSuffix("inventory") { return DebugMemberFixtures.inventory }
        if path.hasSuffix("activity") { return DebugMemberFixtures.activity }
        if path.hasSuffix("my-bookings") { return DebugMemberFixtures.bookings }
        if path.hasSuffix("events") { return DebugMemberFixtures.events }
        if path.contains("/events/") { return first(DebugMemberFixtures.events) }
        if path.hasSuffix("spaces") { return DebugMemberFixtures.spaces }
        if path.hasSuffix("member-card") { return DebugMemberFixtures.card }
        guard path.contains("notifications/inbox/") else { return nil }
        lock.lock(); defer { lock.unlock() }
        var object = (try? JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.inbox.utf8))) as? [String: Any] ?? [:]
        var rows = object["results"] as? [[String: Any]] ?? []
        if path.hasSuffix("read-all") {
            readIDs.formUnion(rows.compactMap { $0["id"] as? Int }); return #"{"updated":2}"#
        }
        if path.hasSuffix("read"), let id = Int(path.split(separator: "/").dropLast().last ?? "") {
            readIDs.insert(id)
            var row = rows.first { $0["id"] as? Int == id } ?? [:]
            row["read_at"] = "2026-10-16T10:00:00Z"; return json(row)
        }
        for index in rows.indices where readIDs.contains(rows[index]["id"] as? Int ?? 0) { rows[index]["read_at"] = "2026-10-16T10:00:00Z" }
        let unread = rows.filter { $0["read_at"] is NSNull }
        if path.hasSuffix("unread-count") { return json(["count": unread.count]) }
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "unread" && $0.value == "true" }) == true { rows = unread }
        object["results"] = rows; object["count"] = rows.count
        return json(object)
    }
    private static func first(_ fixture: String, id: Int? = nil) -> String {
        let object = try? JSONSerialization.jsonObject(with: Data(fixture.utf8))
        let rows = (object as? [[String: Any]]) ?? ((object as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        return json(rows.first(where: { id == nil || $0["id"] as? Int == id }) ?? [:])
    }
    private static func json(_ object: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), as: UTF8.self) }
}
#endif
