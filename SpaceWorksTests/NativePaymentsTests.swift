import XCTest
import UIKit
import StripePaymentSheet
@testable import SpaceWorks

final class NativePaymentsTests: XCTestCase {
    @MainActor func testStripeAppearanceReceivesUnscaledBrandBaseUnderBothContentSizeTraits() {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
                let appearance = NativePayments.stripeAppearance()
                XCTAssertEqual(appearance.font.base.fontName, "Gilroy-Regular")
                XCTAssertEqual(appearance.font.base.pointSize, UIFont.systemFontSize)
                XCTAssertEqual(appearance.font.sizeScaleFactor, 1)
            }
        }
    }

    func testSecretKeysAndIncompleteCustomerConfigurationNeverLaunchStripe() {
        XCTAssertFalse(NativePaymentInput.stripeIsValid(key: "sk_live_private", secret: "pi_1_secret_1", customer: nil, ephemeralKey: nil))
        XCTAssertFalse(NativePaymentInput.stripeIsValid(key: "pk_test_public", secret: "", customer: nil, ephemeralKey: nil))
        XCTAssertFalse(NativePaymentInput.stripeIsValid(key: "pk_test_public", secret: "pi_1_secret_1", customer: "cus_1", ephemeralKey: nil))
        XCTAssertTrue(NativePaymentInput.stripeIsValid(key: "pk_test_public", secret: "pi_1_secret_1", customer: "cus_1", ephemeralKey: "ek_test_1"))
    }

    func testRazorpayRequiresServerOrderPositiveAmountAndCurrency() {
        XCTAssertFalse(NativePaymentInput.razorpayIsValid(key: "rzp_test_public", order: "", amount: 500, currency: "INR"))
        XCTAssertFalse(NativePaymentInput.razorpayIsValid(key: "rzp_test_public", order: "order_1", amount: 0, currency: "INR"))
        XCTAssertFalse(NativePaymentInput.razorpayIsValid(key: "rzp_test_public", order: "order_1", amount: 500, currency: "inr"))
        XCTAssertTrue(NativePaymentInput.razorpayIsValid(key: "rzp_test_public", order: "order_1", amount: 500, currency: "INR"))
    }

    @MainActor func testDemoCannotOpenEitherProviderEvenWithConfiguredInputs() {
        let payments = NativePayments()
        var outcomes: [NativePaymentOutcome] = []
        payments.presentStripe(clientSecret: "pi_1_secret_1", publishableKey: "pk_test_public", isDemo: true, from: UIViewController()) { outcomes.append($0) }
        payments.presentRazorpay(keyID: "rzp_test_public", orderID: "order_1", amountMinor: 500, currency: "INR", isDemo: true, from: UIViewController()) { outcomes.append($0) }
        XCTAssertEqual(outcomes, Array(repeating: .unavailable("Demo mode does not open a payment provider."), count: 2))
        XCTAssertFalse(payments.hasInFlightPayment)
    }

    @MainActor func testLateAndDuplicateCallbacksCannotCompleteAnotherAttempt() throws {
        let callback = NativePaymentCallback()
        var results: [NativePaymentOutcome] = []
        let first = try XCTUnwrap(callback.begin { results.append($0) })
        XCTAssertNil(callback.begin { _ in XCTFail("A second checkout cannot replace the first") })
        callback.cancel()
        let second = try XCTUnwrap(callback.begin { results.append($0) })
        XCTAssertFalse(callback.finish(.awaitingServerConfirmation, id: first))
        XCTAssertTrue(callback.isActive)
        XCTAssertTrue(callback.finish(.awaitingServerConfirmation, id: second))
        XCTAssertFalse(callback.finish(.awaitingServerConfirmation, id: second))
        XCTAssertEqual(results, [.cancelled, .awaitingServerConfirmation])
    }

    @MainActor func testSDKReferencesAreReleasedBeforeCompletionCanStartAnotherPayment() throws {
        let callback = NativePaymentCallback()
        var released = false
        var next: UUID?
        let first = try XCTUnwrap(callback.begin { _ in
            XCTAssertTrue(released)
            next = callback.begin { _ in }
        })
        callback.finish(.cancelled, id: first, beforeCallback: { released = true })
        XCTAssertNotNil(next)
        XCTAssertTrue(callback.isActive)
    }
}
