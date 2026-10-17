import XCTest

/// Native bars can overlap the accessibility scroll frame. Keep gestures in visible content.
enum NativeUIActions {
    static func tap(_ element: XCUIElement, in app: XCUIApplication) {
        var reviewDown = false
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
                // A fitting review button must reveal its entire label before activation.
                // Its midpoint can be hittable while the second line is below the screen.
                let isReviewButton = scroll.identifier == "request-review-scroll" && element.elementType == .button
                let reviewViewport = isReviewButton ? visibleContent(scroll, app, gestureInset: 0) : viewport
                let fullReviewButton = isReviewButton && frame.height > 0 && frame.height <= reviewViewport.height - 4
                // Gesture margins keep drags away from chrome; they are not clipping.
                // Check the complete review control against the actual bar-adjusted
                // viewport, with a 2pt safety margin, rather than its 8pt drag inset.
                let positioned = fullReviewButton ? reviewViewport.insetBy(dx: 2, dy: 2).contains(frame)
                    : viewport.insetBy(dx: 2, dy: 2).contains(CGPoint(x: frame.midX, y: frame.midY))
                if element.isHittable, !visible.isNull, visible.width > 4, visible.height > 4, positioned {
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
                if scroll.identifier == "request-review-scroll" {
                    // Native geometry proves this target remains in the same modal.
                    // Some drags can make no progress; do not reverse a resumed
                    // search merely because half the gesture budget elapsed.
                    if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0 {
                        if frame.maxY <= viewport.minY { reviewDown = true }
                        else if frame.minY >= viewport.maxY { reviewDown = false }
                        else if frame.minY < viewport.minY { reviewDown = true }
                        else if frame.maxY > viewport.maxY { reviewDown = false }
                    }
                    drag(scroll, app, target: element, down: reviewDown)
                } else { drag(scroll, app, target: element, down: attempt >= 12) }
            } else {
                drag(scroll, app, target: element, down: scroll.identifier == "request-review-scroll" ? reviewDown : attempt >= 12)
            }
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
    private static func visibleContent(_ scroll: XCUIElement, _ app: XCUIApplication, gestureInset: CGFloat = 8) -> CGRect {
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
        return viewport.insetBy(dx: gestureInset, dy: gestureInset)
    }
    private static func drag(_ scroll: XCUIElement, _ app: XCUIApplication, target: XCUIElement, down: Bool) {
        let viewport = visibleContent(scroll, app)
        guard viewport.width > 20, viewport.height > 30 else { return }
        // Drag entirely inside the actual visible content, never across tab/navigation bars.
        // A fast released drag flung landscape content ~300pt across a 139pt
        // viewport. Hold at a slow, bounded endpoint so the next visible target is
        // examined before momentum can carry it under the navigation/tab bars.
        var distance = min(200, viewport.height * 0.4)
        if scroll.identifier == "request-review-scroll", target.exists {
            let frame = target.frame
            if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0, frame.height <= viewport.height - 4 {
                let inset = viewport.insetBy(dx: 2, dy: 2)
                let remaining = down ? inset.minY - frame.minY : frame.maxY - inset.maxY
                if remaining > 0 {
                    // Native traces move 190pt for a 200pt drag (10pt pan slop).
                    // Approach the exposed edge precisely in short landscape content.
                    distance = min(distance, max(12, remaining + 10))
                }
            }
        }
        // The modal's multiline purpose field owns an inner scroll; its gutter
        // moves the parent. A generic tablet viewport may include the sidebar, so
        // keep other gestures within the target's horizontal content column.
        var x = viewport.midX
        if scroll.identifier == "request-review-scroll", target.exists {
            // Stay inside the card's padding. The outer screen gutter can be
            // captured by the sheet's pan recognizer instead of its scroll view.
            // The purpose editor begins at the target's leading content edge.
            let leading = target.frame.minX
            if leading.isFinite {
                x = min(viewport.maxX - 12, max(viewport.minX + 12, leading - 12))
            }
        } else if target.exists {
            let frame = target.frame
            if frame.minX.isFinite, frame.maxX.isFinite, frame.width > 0 {
                let lower = max(viewport.minX, frame.minX), upper = min(viewport.maxX, frame.maxX)
                if upper - lower > 24 { x = (lower + upper) / 2 }
            }
        }
        let start = CGPoint(x: x, y: viewport.midY + (down ? -distance : distance) / 2)
        let end = CGPoint(x: x, y: viewport.midY + (down ? distance : -distance) / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}
