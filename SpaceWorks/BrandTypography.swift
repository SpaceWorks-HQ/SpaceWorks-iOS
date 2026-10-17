import SwiftUI
import UIKit

/// Choose the supplied face by PostScript name: all upstream OS/2 weight fields are 400.
enum BrandTypography {
    enum Weight: Int, CaseIterable {
        case regular, medium, semibold, bold
        func face(boldText: Bool) -> String {
            let index = boldText ? [2, 3, 3, 3][rawValue] : rawValue
            return ["Gilroy-Regular", "Gilroy-Medium", "Gilroy-SemiBold", "Gilroy-Bold"][index]
        }
    }
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
    static func font(_ style: Font.TextStyle, weight: Weight, boldText: Bool) -> Font {
        .custom(weight.face(boldText: boldText), size: size(style), relativeTo: style)
    }
    static func unscaledFont(size: CGFloat, weight: Weight = .regular, boldText: Bool = false) -> UIFont {
        guard let font = UIFont(name: weight.face(boldText: boldText), size: size) else {
            preconditionFailure("Missing registered Space Works font")
        }
        return font
    }
    static func uiFont(style: UIFont.TextStyle = .body, weight: Weight = .regular,
                       traits: UITraitCollection, boldText: Bool) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        let font = unscaledFont(size: base, weight: weight, boldText: boldText)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, compatibleWith: traits)
    }
}

private struct BrandFont: ViewModifier {
    var style: Font.TextStyle
    var weight: BrandTypography.Weight
    @Environment(\.legibilityWeight) private var legibilityWeight
    func body(content: Content) -> some View {
        content.font(BrandTypography.font(style, weight: weight, boldText: legibilityWeight == .bold))
    }
}

extension View {
    func brandFont(_ style: Font.TextStyle, weight: BrandTypography.Weight? = nil) -> some View {
        modifier(BrandFont(style: style, weight: weight ?? (style == .headline ? .semibold : .regular)))
    }
}
