import XCTest

/// Native bars can overlap the accessibility scroll frame. Keep gestures in visible content.
enum NativeUIActions {
    static func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<24 {
            let scroll = containingScroll(element, app)
            if element.exists {
                let insideScroll = contains(element, scroll)
                if element.isHittable && !insideScroll { element.tap(); return }
                let frame = element.frame
                let viewport = visibleContent(scroll, app)
                let visible = frame.intersection(viewport)
                print("Native action \(element.identifier.isEmpty ? element.label : element.identifier), attempt \(attempt), frame \(frame), viewport \(viewport), hittable \(element.isHittable)")
                // A SwiftUI Toggle can expose a label rectangle that differs from its
                // native UISwitch activation point. Let XCTest activate a visible switch.
                if element.elementType == .switch, element.isHittable,
                   !visible.isNull, visible.width > 4, visible.height > 4 { element.tap(); return }
                if element.isHittable, !visible.isNull, visible.width > 4, visible.height > 4,
                   viewport.insetBy(dx: 2, dy: 2).contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    // Use the native activation point. A wide Toggle's label centre is not
                    // its switch thumb; coordinates are only needed for clipped text fields.
                    element.tap(); return
                }
                if (element.elementType == .textField || element.elementType == .secureTextField),
                   element.isHittable, !visible.isNull, visible.width > 8, visible.height > 8 {
                    element.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX - frame.minX, dy: visible.midY - frame.minY)).tap(); return
                }
                // Off-screen accessibility frames can jump across the viewport after
                // rotation. Reversing on their midpoint oscillated around hidden controls.
                // Sweep consistently in each direction; activation still requires a real
                // visible, hittable target. New screens normally start near their top.
                drag(scroll, app, down: attempt >= 12)
            } else { drag(scroll, app, down: attempt >= 12) }
        }
        XCTFail("Action must be reachable after scrolling visible content.")
    }
    private static func contains(_ element: XCUIElement, _ scroll: XCUIElement) -> Bool {
        guard element.exists, scroll.exists else { return false }
        let descendants = scroll.descendants(matching: element.elementType)
        if !element.identifier.isEmpty { return descendants.matching(identifier: element.identifier).firstMatch.exists }
        guard !element.label.isEmpty else { return false }
        return descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
    }
    private static func containingScroll(_ element: XCUIElement, _ app: XCUIApplication) -> XCUIElement {
        let scrolls = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        // Presented SwiftUI sheets may appear in a backing view's AX descendants.
        // Its scroll cannot move the modal content. Prefer the actual review container.
        if let review = scrolls.first(where: { $0.identifier == "request-review-scroll" }) { return review }
        let containing = scrolls.filter { contains(element, $0) }
        return containing.min(by: { area($0.frame.intersection(app.frame)) < area($1.frame.intersection(app.frame)) })
            ?? scrolls.first ?? app.scrollViews.firstMatch
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? .greatestFiniteMagnitude : rect.width * rect.height }
    private static func visibleContent(_ scroll: XCUIElement, _ app: XCUIApplication) -> CGRect {
        var viewport = scroll.exists ? scroll.frame.intersection(app.frame) : app.frame
        // SwiftUI's accessibility ScrollView frame includes content UNDER native bars.
        // A target can be marked hittable there while its coordinate activates another tab.
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            let frame = bar.frame
            if frame.intersects(viewport), frame.midY < viewport.midY {
                let bottom = viewport.maxY; viewport.origin.y = max(viewport.minY, frame.maxY); viewport.size.height = max(0, bottom - viewport.minY)
            }
        }
        // A tab bar hidden behind a modal is not part of the modal viewport.
        let lowerBars = app.tabBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            + app.keyboards.allElementsBoundByIndex.filter { $0.exists }
        for bar in lowerBars {
            let frame = bar.frame
            if frame.intersects(viewport), frame.midY > viewport.minY { viewport.size.height = max(0, min(viewport.maxY, frame.minY) - viewport.minY) }
        }
        return viewport.insetBy(dx: 8, dy: 8)
    }
    private static func drag(_ scroll: XCUIElement, _ app: XCUIApplication, down: Bool) {
        let viewport = visibleContent(scroll, app)
        guard viewport.width > 20, viewport.height > 30 else { return }
        // Drag entirely inside the actual visible content, never across tab/navigation bars.
        // A fast released drag flung landscape content ~300pt across a 139pt
        // viewport. Hold at a slow, bounded endpoint so the next visible target is
        // examined before momentum can carry it under the navigation/tab bars.
        let distance = min(200, viewport.height * 0.4)
        let start = CGPoint(x: viewport.midX, y: viewport.midY + (down ? -distance : distance) / 2)
        let end = CGPoint(x: viewport.midX, y: viewport.midY + (down ? distance : -distance) / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}
