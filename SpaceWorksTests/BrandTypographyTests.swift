import CoreText
import SwiftUI
import XCTest
@testable import SpaceWorks

@MainActor final class BrandTypographyTests: XCTestCase {
    func testAllSuppliedFacesLoadWithoutSystemFallbackAndContainInterfaceGlyphs() throws {
        for name in ["Gilroy-Regular", "Gilroy-Medium", "Gilroy-SemiBold", "Gilroy-Bold"] {
            let font = try XCTUnwrap(UIFont(name: name, size: 17))
            XCTAssertEqual(font.fontName, name)
            let characters = Array("Space Works 0123456789".utf16)
            var glyphs = Array(repeating: CGGlyph(), count: characters.count)
            let coreTextFont = CTFontCreateWithName(font.fontName as CFString, 17, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(coreTextFont) as String, name)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(coreTextFont, characters, &glyphs, characters.count))
            XCTAssertFalse(glyphs.contains(0))
        }
    }

    func testUIKitMetricsScaleActualGilroyFromDefaultToLargestAccessibilityCategory() {
        let normal = BrandTypography.uiFont(traits: UITraitCollection(preferredContentSizeCategory: .large), boldText: false)
        let enlarged = BrandTypography.uiFont(traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), boldText: false)
        XCTAssertEqual(normal.fontName, "Gilroy-Regular")
        XCTAssertEqual(enlarged.fontName, "Gilroy-Regular")
        XCTAssertGreaterThan(enlarged.pointSize, normal.pointSize * 2)
        XCTAssertGreaterThan(enlarged.lineHeight, normal.lineHeight)
    }

    func testNativeLegibilityTraitUsesRealHeavierFaceAndKeepsAccessibilityScaling() {
        // This is an explicit native trait test, not a claim that the OS Bold Text setting changed.
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(legibilityWeight: .bold),
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)])
        let font = BrandTypography.uiFont(traits: traits, boldText: traits.legibilityWeight == .bold)
        XCTAssertEqual(font.fontName, "Gilroy-SemiBold")
        XCTAssertGreaterThan(font.pointSize, 34)
        let heading = BrandTypography.uiFont(style: .headline, weight: .semibold, traits: traits, boldText: true)
        XCTAssertEqual(heading.fontName, "Gilroy-Bold")
    }

    func testPasswordRepresentableRefreshesFontWhenSwiftUITypeAndLegibilityChange() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let password = "Synthetic font test"
        let host = UIHostingController(rootView: AnyView(PasswordEntry(text: .constant(password), identifier: "brand-password")
            .dynamicTypeSize(.large).environment(\.legibilityWeight, .regular)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        func field(in view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            return view.subviews.compactMap { field(in: $0) }.first
        }
        host.view.layoutIfNeeded()
        let input = try XCTUnwrap(field(in: host.view))
        let original = try XCTUnwrap(input.font)
        XCTAssertEqual(original.fontName, "Gilroy-Regular")
        XCTAssertEqual(input.text, password)
        host.rootView = AnyView(PasswordEntry(text: .constant(password), identifier: "brand-password")
            .dynamicTypeSize(.accessibility5).environment(\.legibilityWeight, .bold))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let fontUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "font.fontName == %@", "Gilroy-SemiBold"), object: input)
        await fulfillment(of: [fontUpdated], timeout: 2)
        host.view.layoutIfNeeded()
        let retained = try XCTUnwrap(field(in: host.view))
        XCTAssertTrue(retained === input)
        XCTAssertEqual(retained.text, password)
        let updated = try XCTUnwrap(retained.font)
        XCTAssertEqual(updated.fontName, "Gilroy-SemiBold")
        XCTAssertGreaterThan(updated.pointSize, original.pointSize * 2)
    }
}
