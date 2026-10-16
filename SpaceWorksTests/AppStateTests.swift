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
    func testLoadingCoalescesRepeatedConnectActions() async {
        let gate = HealthGate()
        let state = AppState(settings: settings()) { _ in await gate.wait() }
        state.serverInput = "https://spaceworks.example"
        let first = Task { await state.connect() }
        while !state.connecting { await Task.yield() }
        XCTAssertTrue(state.connecting)
        await state.connect()
        await gate.finish()
        await first.value
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(state.screen, .shell)
        XCTAssertFalse(state.connecting)
    }
    func testRestoredServerIsRevalidatedOnlyOnceAndCanBeChanged() async {
        let defaults = settings()
        defaults.set("https://spaceworks.example", forKey: "server-origin")
        let state = AppState(settings: defaults) { _ in }
        await state.restore()
        XCTAssertEqual(state.screen, .shell)
        state.changeServer()
        await state.restore()
        XCTAssertEqual(state.screen, .connect)
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
    func testNativeNavigationAndEveryTabLayoutMeetTextContrastInBothModes() throws {
        func luminance(_ color: UIColor, _ traits: UITraitCollection) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            let values = [r, g, b].map { value -> Double in
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        func check(_ ink: UIColor?, on background: UIColor?, traits: UITraitCollection) throws {
            let values = try [luminance(XCTUnwrap(ink), traits), luminance(XCTUnwrap(background), traits)].sorted()
            XCTAssertGreaterThanOrEqual((values[1] + 0.05) / (values[0] + 0.05), 4.5)
        }
        let navigation = NativeAppearance.navigation()
        let tabs = NativeAppearance.tabs()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            try check(navigation.titleTextAttributes[.foregroundColor] as? UIColor, on: navigation.backgroundColor, traits: traits)
            try check(navigation.largeTitleTextAttributes[.foregroundColor] as? UIColor, on: navigation.backgroundColor, traits: traits)
            for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
                for state in [layout.normal, layout.selected] {
                    try check(state.titleTextAttributes[.foregroundColor] as? UIColor, on: tabs.backgroundColor, traits: traits)
                    try check(state.iconColor, on: tabs.backgroundColor, traits: traits)
                    try check(state.badgeTextAttributes[.foregroundColor] as? UIColor, on: state.badgeBackgroundColor, traits: traits)
                }
            }
        }
    }
}

private actor HealthGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var calls = 0
    func wait() async {
        calls += 1
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { released = true; continuation?.resume(); continuation = nil }
}
