import SwiftUI

/// Geometry-only diagnostics for native UI tests. No content, credentials or gestures are exposed.
extension View {
    @ViewBuilder func requestScrollDiagnostics() -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            self.overlay(alignment: .center) {
                ReviewScrollProbe().frame(width: 1, height: 1).allowsHitTesting(false)
            }
        } else { self }
        #else
        self
        #endif
    }
}

#if DEBUG
import UIKit

private struct ReviewScrollProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ReviewScrollProbeView { ReviewScrollProbeView() }
    func updateUIView(_ view: ReviewScrollProbeView, context: Context) {}
}

private final class ReviewScrollProbeView: UIView {
    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "review-scroll-diagnostics"
        accessibilityLabel = "Review scroll geometry"
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { return nil }
    override var accessibilityValue: String? {
        get {
            guard let window else { return "No attached window" }
            var remaining = 512
            func scrolls(_ view: UIView, depth: Int) -> [[String: String]] {
                guard depth < 40, remaining > 0 else { return [] }
                remaining -= 1
                var result: [[String: String]] = []
                if let scroll = view as? UIScrollView {
                    result.append([
                        "class": String(describing: type(of: scroll)),
                        "windowFrame": String(describing: scroll.convert(scroll.bounds, to: window)),
                        "bounds": String(describing: scroll.bounds),
                        "contentSize": String(describing: scroll.contentSize),
                        "offset": String(describing: scroll.contentOffset),
                        "insets": String(describing: scroll.adjustedContentInset),
                        "enabled": String(scroll.isScrollEnabled),
                        "pan": String(scroll.panGestureRecognizer.state.rawValue)
                    ])
                }
                for child in view.subviews { result += scrolls(child, depth: depth + 1) }
                return result
            }
            func hit(_ point: CGPoint) -> [String] {
                var view = window.hitTest(point, with: nil)
                var result = [String(describing: point)]
                while let current = view, result.count < 20 {
                    result.append(String(describing: type(of: current)))
                    view = current.superview
                }
                return result
            }
            let metadata: [String: Any] = [
                "scrolls": scrolls(window, depth: 0),
                "leadingHit": hit(CGPoint(x: 36, y: 590.5)),
                "centreHit": hit(CGPoint(x: window.bounds.midX, y: 590.5))
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else { return "Geometry unavailable" }
            return String(decoding: data, as: UTF8.self)
        }
        set { super.accessibilityValue = newValue }
    }
}
#endif
