import SwiftUI
import SpaceWorksAPI

@main
struct SpaceWorksApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            UserDefaults.standard.removeObject(forKey: "server-origin")
            UserDefaults.standard.removeObject(forKey: "dark-mode")
            URLProtocol.registerClass(PreviewHealthProtocol.self)
        }
        #endif
    }
    var body: some Scene {
        WindowGroup { RootView() }
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
        let failure = ProcessInfo.processInfo.arguments.contains("--health-unavailable")
        let code = failure ? 503 : 200
        let body = failure ? #"{"detail":"Try again later.","code":"service_unavailable"}"# : #"{"status":"ok"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
