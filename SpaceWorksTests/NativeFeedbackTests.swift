import XCTest
import UIKit
@testable import SpaceWorks

@MainActor final class NativeFeedbackTests: XCTestCase {
    func testNativeActivationNotificationsRejectDeferredAndBackgroundFeedback() {
        let notifications = NotificationCenter()
        let lifecycle = NativeFeedbackLifecycle(initiallyActive: true, notifications: notifications)
        defer { lifecycle.stop() }
        let foreground = NativeFeedbackEvent(.success, lifecycle: lifecycle)
        XCTAssertTrue(lifecycle.accepts(foreground))
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        let backgroundCompletion = NativeFeedbackEvent(.success, lifecycle: lifecycle)
        XCTAssertFalse(lifecycle.accepts(foreground)); XCTAssertFalse(lifecycle.accepts(backgroundCompletion))
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        // Model a SwiftUI callback deferred until the next active scene. Neither old event replays.
        XCTAssertFalse(lifecycle.accepts(foreground)); XCTAssertFalse(lifecycle.accepts(backgroundCompletion))
        XCTAssertTrue(lifecycle.accepts(NativeFeedbackEvent(.selection, lifecycle: lifecycle)))
        lifecycle.stop()
        XCTAssertFalse(lifecycle.accepts(NativeFeedbackEvent(.success, lifecycle: lifecycle)))
    }

    func testClosingFormRetiresInFlightFeedbackWhileFreshAcknowledgementStillEmits() async throws {
        let gate = FeedbackOperationGate()
        defer { Task { await gate.release() } }
        let form = AccountAccessState(step: .signUp, create: { _, _, _, _ in await gate.suspend() },
                                     request: { _ in }, reset: { _, _, _ in })
        form.name = "Sample Maker"; form.email = "maker@example.test"
        form.password = "sample-password"; form.confirmation = form.password
        let operation = Task { await form.signUp() }
        for _ in 0..<500 {
            if await gate.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await gate.started
        form.retireFeedback()
        await gate.release(); await operation.value
        XCTAssertTrue(started); XCTAssertEqual(form.step, .created); XCTAssertNil(form.feedback)
        let fresh = AccountAccessState(step: .signUp, create: { _, _, _, _ in }, request: { _ in }, reset: { _, _, _ in })
        fresh.name = "Sample Maker"; fresh.email = "maker@example.test"
        fresh.password = "sample-password"; fresh.confirmation = fresh.password
        await fresh.signUp(); XCTAssertEqual(fresh.feedback?.kind, .success)
    }

    func testCancellationIsQuietAndExplicitValidationHasNoTransportSideEffect() async {
        var requests = 0
        let form = AccountAccessState(step: .requestReset, create: { _, _, _, _ in }, request: { _ in
            requests += 1; throw CancellationError()
        }, reset: { _, _, _ in })
        await form.requestCode(); XCTAssertEqual(form.feedback?.kind, .error); XCTAssertEqual(requests, 0)
        form.retireFeedback(); form.email = "maker@example.test"
        await form.requestCode(); XCTAssertEqual(requests, 1); XCTAssertNil(form.feedback)
    }
}

private actor FeedbackOperationGate {
    private(set) var started = false
    private var open = false
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        started = true
        if !open { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}
