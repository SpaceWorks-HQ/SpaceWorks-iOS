import XCTest
import SwiftUI
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor
final class AppStateTests: XCTestCase {
    private func settings() -> UserDefaults {
        let name = "test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    func testConnectValidatesHealthBeforePersistingAndOpeningShell() async {
        let defaults = settings()
        let state = AppState(settings: defaults) { origin in XCTAssertEqual(origin.url.absoluteString, "https://spaceworks.example") }
        state.serverInput = "https://spaceworks.example/"
        await state.connect()
        XCTAssertEqual(state.screen, .shell)
        XCTAssertFalse(state.connecting)
        XCTAssertNil(state.error)
        XCTAssertEqual(defaults.string(forKey: "server-origin"), "https://spaceworks.example")
        let restored = AppState(settings: defaults) { _ in }
        XCTAssertEqual(restored.serverInput, "https://spaceworks.example")
        state.changeServer()
        XCTAssertEqual(state.screen, .connect)
        XCTAssertNil(defaults.string(forKey: "server-origin"))
    }
    func testInvalidURLAndFailedHealthStayOnConnectWithoutPersisting() async {
        let defaults = settings()
        let state = AppState(settings: defaults) { _ in throw APIError(status: 503, code: "maintenance", detail: "Try again later.") }
        state.serverInput = "http://unsafe.example"
        await state.connect()
        XCTAssertEqual(state.error, "Enter a valid HTTPS server URL.")
        state.serverInput = "https://spaceworks.example"
        await state.connect()
        XCTAssertEqual(state.error, "Try again later.")
        XCTAssertEqual(state.screen, .connect)
        XCTAssertNil(defaults.string(forKey: "server-origin"))
        XCTAssertFalse(state.connecting)
    }
    func testLockedBrandCannotChangeServer() async {
        let defaults = settings()
        defaults.set("https://old.example", forKey: "server-origin")
        let state = AppState(lockedServer: "https://locked.example", settings: defaults) { _ in }
        XCTAssertTrue(state.locked)
        XCTAssertEqual(state.serverInput, "https://locked.example")
        await state.connect()
        state.changeServer()
        XCTAssertEqual(state.screen, .shell)
        XCTAssertEqual(state.serverInput, "https://locked.example")
    }
    func testThrottlingIsPreservedUntilServerChanges() async {
        let state = AppState(settings: settings()) { _ in
            throw APIError(status: 429, code: "throttled", detail: "Slow down.", retryAfter: Date().addingTimeInterval(120))
        }
        state.serverInput = "https://spaceworks.example"
        await state.connect()
        XCTAssertNotNil(state.retryAfter)
        state.serverInput = "https://other.example"
        XCTAssertNil(state.retryAfter)
        XCTAssertNil(state.error)
    }
    func testAppearancePersistsAndOnlyMemberTabsExist() {
        let defaults = settings()
        let state = AppState(settings: defaults) { _ in }
        XCTAssertFalse(state.darkMode)
        state.toggleAppearance()
        XCTAssertTrue(AppState(settings: defaults).darkMode)
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["Home", "Inventory", "Activity", "Inbox", "Profile"])
    }
    func testGeneratedBrandIsConsumedByBuiltApp() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, Brand.appName)
        XCTAssertEqual(Bundle.main.bundleIdentifier, Brand.bundleID)
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        XCTAssertNotNil(icons?["CFBundlePrimaryIcon"])
    }
    func testSemanticAssetsMatchTokenValuesInBothModes() throws {
        func color(_ name: String, _ style: UIUserInterfaceStyle) throws -> [Int] {
            let value = try XCTUnwrap(UIColor(named: name)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            value.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b].map { Int(($0 * 255).rounded()) }
        }
        XCTAssertEqual(try color("bg", .light), [255, 244, 232])
        XCTAssertEqual(try color("bg", .dark), [20, 44, 42])
        XCTAssertEqual(try color("accent", .light), [0, 110, 99])
        XCTAssertEqual(try color("ink", .dark), [255, 244, 232])
    }
}
