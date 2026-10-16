import SwiftUI
import UIKit
#if canImport(StripePaymentSheet)
import StripePaymentSheet
import StripePayments
import StripeCore
#endif
#if canImport(Razorpay)
import Razorpay
import RazorpayCore
#endif

enum NativePaymentOutcome: Equatable {
    case awaitingServerConfirmation
    case cancelled
    case failed(String)
    case unavailable(String)
}

/// SDK parameters only: these are not transport models. The generated API gateway selects the vendor.
enum NativePaymentInput {
    static func stripeIsValid(key: String, secret: String, customer: String?, ephemeralKey: String?) -> Bool {
        let keyValid = key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_")
        let secretValid = secret.hasPrefix("pi_") && secret.contains("_secret_")
        let customerValid = (customer == nil && ephemeralKey == nil) ||
            (customer?.hasPrefix("cus_") == true && ephemeralKey?.hasPrefix("ek_") == true)
        return keyValid && secretValid && customerValid
    }

    static func razorpayIsValid(key: String, order: String, amount: Int64, currency: String) -> Bool {
        (key.hasPrefix("rzp_test_") || key.hasPrefix("rzp_live_")) && order.hasPrefix("order_") &&
            amount > 0 && currency.count == 3 && currency.unicodeScalars.allSatisfy { (65...90).contains(Int($0.value)) }
    }
}

@MainActor final class NativePayments: NSObject {
    private let callback = NativePaymentCallback()
    private var resetting = false
    private weak var presenter: UIViewController?
    #if canImport(StripePaymentSheet)
    private var stripe: PaymentSheet?
    #endif
    #if canImport(Razorpay)
    private var razorpay: Razorpay.RazorpayCheckout?
    private var razorpayCallbacks: RazorpayCallbacks?
    #endif
    var hasInFlightPayment: Bool { callback.isActive }

    func presentStripe(clientSecret: String, publishableKey: String, customerID: String? = nil,
                       ephemeralKey: String? = nil, returnURL: URL? = nil, isDemo: Bool,
                       from controller: UIViewController, completion: @escaping (NativePaymentOutcome) -> Void) {
        guard !isDemo else { completion(.unavailable("Demo mode does not open a payment provider.")); return }
        guard NativePaymentInput.stripeIsValid(key: publishableKey, secret: clientSecret, customer: customerID, ephemeralKey: ephemeralKey) else {
            completion(.unavailable("Payment setup is unavailable. Contact your makerspace.")); return
        }
        #if canImport(StripePaymentSheet)
        guard let attempt = begin(from: controller, completion: completion) else { return }
        var configuration = PaymentSheet.Configuration()
        configuration.apiClient = STPAPIClient(publishableKey: publishableKey)
        configuration.merchantDisplayName = Brand.appName
        configuration.returnURL = returnURL?.absoluteString
        if let customerID, let ephemeralKey {
            configuration.customer = .init(id: customerID, ephemeralKeySecret: ephemeralKey)
        }
        configuration.appearance.colors.primary = UIColor(Color.swAccentInk)
        configuration.appearance.colors.background = UIColor(Color.swPanel)
        configuration.appearance.colors.componentBackground = UIColor(Color.swSurface)
        configuration.appearance.colors.componentBorder = UIColor(Color.swOutline)
        configuration.appearance.colors.componentDivider = UIColor(Color.swLine)
        configuration.appearance.colors.text = UIColor(Color.swInk)
        configuration.appearance.colors.textSecondary = UIColor(Color.swMuted)
        configuration.appearance.colors.componentText = UIColor(Color.swInk)
        configuration.appearance.colors.componentPlaceholderText = UIColor(Color.swMuted)
        configuration.appearance.colors.icon = UIColor(Color.swMuted)
        configuration.appearance.colors.danger = UIColor(Color.swDanger)
        configuration.appearance.cornerRadius = 10
        configuration.appearance.borderWidth = 1
        configuration.appearance.shadow = .disabled
        configuration.appearance.primaryButton.backgroundColor = UIColor(Color.swAccent)
        configuration.appearance.primaryButton.textColor = UIColor(Color.swOnAccent)
        configuration.appearance.primaryButton.height = 48
        configuration.appearance.primaryButton.successBackgroundColor = UIColor(Color.swSuccessSoft)
        configuration.appearance.primaryButton.successTextColor = UIColor(Color.swSuccessInk)
        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        stripe = sheet
        sheet.present(from: controller) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .completed: self?.finish(.awaitingServerConfirmation, id: attempt)
                case .canceled: self?.finish(.cancelled, id: attempt)
                case .failed: self?.finish(.failed("Payment could not be completed. Check its status before trying again."), id: attempt)
                }
            }
        }
        #else
        completion(.unavailable("The payment SDK is not configured in this build."))
        #endif
    }

    /// Never call until the authoritative contract supplies server-selected Razorpay SDK parameters.
    func presentRazorpay(keyID: String, orderID: String, amountMinor: Int64, currency: String, isDemo: Bool,
                         from controller: UIViewController, completion: @escaping (NativePaymentOutcome) -> Void) {
        guard !isDemo else { completion(.unavailable("Demo mode does not open a payment provider.")); return }
        guard NativePaymentInput.razorpayIsValid(key: keyID, order: orderID, amount: amountMinor, currency: currency) else {
            completion(.unavailable("Payment setup is unavailable. Contact your makerspace.")); return
        }
        #if canImport(Razorpay)
        guard let attempt = begin(from: controller, completion: completion) else { return }
        let delegate = RazorpayCallbacks { [weak self] result in self?.finish(result, id: attempt) }
        razorpayCallbacks = delegate
        razorpay = Razorpay.RazorpayCheckout.initWithKey(keyID, andDelegateWithData: delegate)
        var options: [AnyHashable: Any] = ["key": keyID, "order_id": orderID, "amount": amountMinor,
                                         "currency": currency, "name": Brand.appName]
        if let color = accentHex(for: controller.traitCollection) { options["theme"] = ["color": color] }
        razorpay?.open(options, displayController: controller)
        #else
        completion(.unavailable("The payment SDK is not configured in this build."))
        #endif
    }

    private func begin(from controller: UIViewController, completion: @escaping (NativePaymentOutcome) -> Void) -> UUID? {
        guard !resetting, !hasInFlightPayment, controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else {
            completion(.unavailable("Payment is not ready to open. Close any open sheet and try again.")); return nil
        }
        presenter = controller
        return callback.begin(completion)
    }

    private func finish(_ outcome: NativePaymentOutcome, id: UUID) {
        callback.finish(outcome, id: id) {
            presenter = nil
            #if canImport(StripePaymentSheet)
            stripe = nil
            #endif
            #if canImport(Razorpay)
            razorpay = nil
            razorpayCallbacks = nil
            #endif
        }
        // Even SDK success only starts server reconciliation. No callback can mark a payment paid.
    }

    func reset() {
        resetting = true
        defer { resetting = false }
        if hasInFlightPayment { presenter?.presentedViewController?.dismiss(animated: false) }
        presenter = nil
        #if canImport(StripePaymentSheet)
        stripe = nil
        PaymentSheet.resetCustomer()
        #endif
        #if canImport(Razorpay)
        razorpay = nil
        razorpayCallbacks = nil
        Razorpay.RazorpayCheckout.clearUserData()
        #endif
        callback.cancel()
    }

    static func handleReturnURL(_ url: URL) -> Bool {
        #if canImport(StripePaymentSheet)
        return StripeAPI.handleURLCallback(with: url)
        #else
        return false
        #endif
    }

    private func accentHex(for traits: UITraitCollection) -> String? {
        let color = UIColor(Color.swAccent).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return "#" + String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

#if canImport(Razorpay)
@MainActor private final class RazorpayCallbacks: NSObject, RazorpayPaymentCompletionProtocolWithData {
    let complete: (NativePaymentOutcome) -> Void
    init(complete: @escaping (NativePaymentOutcome) -> Void) { self.complete = complete }
    nonisolated func onPaymentSuccess(_ payment_id: String, andData response: [AnyHashable: Any]?) {
        Task { @MainActor [weak self] in self?.complete(.awaitingServerConfirmation) }
    }
    nonisolated func onPaymentError(_ code: Int32, description str: String, andData response: [AnyHashable: Any]?) {
        Task { @MainActor [weak self] in
            self?.complete(code == 2 ? .cancelled : .failed("Payment could not be completed. Check its status before trying again."))
        }
    }
}
#endif
