import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class AppState {
    enum Screen: Equatable { case connect, shell }
    var screen: Screen = .connect
    var serverInput = "" {
        didSet { if oldValue != serverInput { error = nil; retryAfter = nil } }
    }
    private(set) var darkMode: Bool
    private(set) var connecting = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    let locked: Bool
    private let settings: UserDefaults
    private let health: @Sendable (ServerOrigin) async throws -> Void
    private var attemptedRestore = false

    init(lockedServer: String? = Brand.serverURL, settings: UserDefaults = .standard,
         health: @escaping @Sendable (ServerOrigin) async throws -> Void = { try await SpaceWorksService(origin: $0).health() }) {
        self.settings = settings
        self.health = health
        darkMode = settings.bool(forKey: "dark-mode")
        locked = lockedServer != nil
        serverInput = lockedServer ?? settings.string(forKey: "server-origin") ?? ""
    }
    func toggleAppearance() {
        darkMode.toggle()
        settings.set(darkMode, forKey: "dark-mode")
    }
    func restore() async {
        guard !attemptedRestore else { return }
        attemptedRestore = true
        if !serverInput.isEmpty { await connect() }
    }

    func connect() async {
        guard !connecting else { return }
        if let retryAfter, retryAfter > Date() { return }
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            #if DEBUG
            let origin = try ServerOrigin(serverInput, allowLocalHTTP: true)
            #else
            let origin = try ServerOrigin(serverInput)
            #endif
            try await health(origin)
            guard !Task.isCancelled else { return }
            settings.set(origin.url.absoluteString, forKey: "server-origin")
            serverInput = origin.url.absoluteString
            screen = .shell
        } catch {
            self.error = APIError.display(error)
            retryAfter = APIError.retryDeadline(error)
        }
    }

    func changeServer() {
        guard !locked else { return }
        settings.removeObject(forKey: "server-origin")
        screen = .connect
    }
}
