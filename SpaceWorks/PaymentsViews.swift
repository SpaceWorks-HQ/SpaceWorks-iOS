import SwiftUI
import Observation
import SpaceWorksAPI
import UIKit

struct PaymentsView: View {
    @Bindable var state: PaymentsState
    @State private var dueFilter: String?
    private var visibleRecords: [Components.Schemas.MemberPayment] {
        state.records.filter { dueFilter == nil || $0.due_state == dueFilter }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Payments").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("See your charges, payment status, and issued documents.").foregroundStyle(Color.swMuted)
                Picker("Due date", selection: $dueFilter) {
                    Text("All charges").tag(String?.none)
                    Text("Overdue").tag(String?("overdue"))
                    Text("Due today").tag(String?("due_today"))
                    Text("Upcoming").tag(String?("upcoming"))
                }.pickerStyle(.menu).frame(minHeight: 48).accessibilityIdentifier("payments-due-filter")
                if state.isDemo { Label("Demo payments · sample data", systemImage: "info.circle").foregroundStyle(Color.swMuted) }
                if !state.canRequest {
                    Text("Please wait until \(state.retryAfter.formatted(date: .omitted, time: .standard)) before trying again.").foregroundStyle(Color.swMuted)
                }
                if case .loading = state.load { ProgressView("Loading payments…") }
                if case .failed(let message) = state.load {
                    SWError(message: message).accessibilityIdentifier("payments-error")
                    Button("Try again") { Task { await state.refresh() } }.frame(minHeight: 48).disabled(!state.canRequest)
                }
                if state.load == .ready && visibleRecords.isEmpty {
                    SWCard {
                        Label(dueFilter == nil ? "No charges here" : "No charges match this filter", systemImage: "checkmark.circle").font(.headline)
                        Text(dueFilter == nil ? "Your payments will appear here when your makerspace issues a charge." : "Choose another filter to see the other charges.").foregroundStyle(Color.swMuted)
                    }
                }
                ForEach(visibleRecords, id: \.id) { row in
                    NavigationLink { PaymentDetailView(state: state, paymentID: row.id) } label: {
                        SWCard {
                            Text(row.subject_label).font(.headline).foregroundStyle(Color.swInk)
                            PaymentMoney(amount: row.amount, currency: row.currency)
                            HStack(alignment: .top) {
                                Text(PaymentCopy.status(row.status?.rawValue)).foregroundStyle(Color.swMuted)
                                Spacer()
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            if let due = row.due_date, !due.isEmpty { Text("Due \(due)").font(.subheadline).foregroundStyle(Color.swMuted) }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("payment-\(row.id)")
                }
                NavigationLink { PaymentDocumentsView(state: state) } label: {
                    Label("Receipts and credit notes", systemImage: "doc.text").frame(minHeight: 48)
                }.accessibilityIdentifier("payment-documents")
            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("Payments").navigationBarTitleDisplayMode(.inline)
            .task { if state.load == .idle { await state.refresh() } }
            .refreshable { await state.refresh() }
    }
}

struct PaymentDetailView: View {
    @Bindable var state: PaymentsState
    let paymentID: Int
    @State private var presentation = PaymentPresentationContext()
    #if DEBUG
    @State private var demoChoice = false
    #endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let row = state.record(paymentID) {
                    Text("Review payment").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(row.subject_label).font(.title2.bold())
                    SWCard {
                        PaymentMoney(amount: row.amount, currency: row.currency).font(.title.bold())
                        Text(PaymentCopy.status(row.status?.rawValue)).font(.headline)
                        if let due = row.due_date, !due.isEmpty { Text("Due \(due)").foregroundStyle(Color.swMuted) }
                        Text("Charge #\(row.id)").font(.subheadline).foregroundStyle(Color.swMuted)
                    }
                    if let settlement = row.settlement?.value1 {
                        SWCard {
                            Text("Received at the desk").font(.headline)
                            Text(settlement.received_at, format: .dateTime.day().month().year().hour().minute()).foregroundStyle(Color.swMuted)
                            Text("Method: \(settlement.method)")
                            if !settlement.reference.isEmpty { Text("Reference: \(settlement.reference)").textSelection(.enabled) }
                        }
                    }
                    checkoutStatus
                    if !state.canRequest {
                        Text("Try again after \(state.retryAfter.formatted(date: .omitted, time: .standard)).").foregroundStyle(Color.swMuted)
                    }
                    if state.canPay(row) {
                        Text("Review the amount above. Your payment provider will open to complete checkout.").foregroundStyle(Color.swMuted)
                        Button("Continue to payment") { startCheckout() }.buttonStyle(SWPrimary())
                            .accessibilityIdentifier("payment-continue")
                    } else if row.status?.rawValue == "pending", !row.online_payment_available {
                        Label("Online payment is unavailable. Ask your makerspace about paying at the desk.", systemImage: "info.circle")
                            .foregroundStyle(Color.swMuted)
                    }
                    Button("Check payment status") { Task { await state.checkStatus(paymentID: paymentID) } }
                        .frame(minHeight: 48).disabled(state.busy || !state.canRequest).accessibilityIdentifier("payment-check-status")
                    if !row.refunds.isEmpty {
                        Text("Refunds").font(.title2.bold())
                        ForEach(Array(row.refunds.enumerated()), id: \.offset) { _, refund in
                            SWCard {
                                PaymentMoney(amount: refund.amount, currency: refund.currency)
                                Text(NativeStatusCopy.label(refund.status)).font(.headline)
                                if !refund.reason.isEmpty { Text(refund.reason).foregroundStyle(Color.swMuted) }
                                if !refund.reference.isEmpty { Text("Reference: \(refund.reference)").foregroundStyle(Color.swMuted).textSelection(.enabled) }
                            }
                        }
                    }
                    NavigationLink("Receipts and credit notes") { PaymentDocumentsView(state: state, paymentID: paymentID) }
                        .frame(minHeight: 48)
                } else {
                    Text("Payment unavailable").font(.title.bold())
                    Text("Refresh your payments to see the latest information.").foregroundStyle(Color.swMuted)
                    Button("Refresh payments") { Task { await state.refresh() } }.frame(minHeight: 48).disabled(!state.canRequest)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("Payment details").navigationBarTitleDisplayMode(.inline)
            .background(PaymentPresentationAnchor(context: presentation).frame(width: 0, height: 0))
            .task { if state.load == .idle { await state.refresh() } }
            #if DEBUG
            .sheet(isPresented: $demoChoice) {
                DemoPaymentOutcomeSheet(state: state, paymentID: paymentID)
            }
            #endif
    }
    @ViewBuilder private var checkoutStatus: some View {
        switch state.checkout {
        case .preparing(let id) where id == paymentID: ProgressView("Preparing checkout…")
        case .presenting(let id) where id == paymentID: ProgressView("Checkout is open…")
        case .checking(let id) where id == paymentID: ProgressView("Checking payment…")
        case .awaiting(let id) where id == paymentID:
            if let message = state.reconciliationError { SWError(message: message) }
            Label("Still waiting for confirmation. You can safely leave and check again later.", systemImage: "clock")
                .foregroundStyle(Color.swMuted).accessibilityIdentifier("payment-awaiting")
            #if DEBUG
            if state.isDemo {
                Button("Preview delayed demo confirmation") { Task { await state.simulateDelayedConfirmation(paymentID: paymentID) } }
                    .frame(minHeight: 48).accessibilityIdentifier("payment-demo-delayed-confirmation")
            }
            #endif
        case .completed(let id) where id == paymentID:
            Label(state.isDemo ? "Demo payment confirmed" : "Payment status confirmed", systemImage: "checkmark.circle")
                .foregroundStyle(Color.swSuccessInk).accessibilityIdentifier("payment-confirmed")
        case .stopped(let id, let message) where id == paymentID:
            SWError(message: message).accessibilityIdentifier("payment-checkout-error")
            if state.requiresStatusRefresh(paymentID) {
                Button("Refresh payment status") { Task { await state.refresh() } }.frame(minHeight: 48).disabled(!state.canRequest)
                    .accessibilityIdentifier("payment-refresh-status")
            }
        default: EmptyView()
        }
    }
    private func startCheckout() {
        #if DEBUG
        if state.isDemo { demoChoice = true; return }
        #endif
        Task {
            guard let (attempt, intent) = await state.prepareCheckout(paymentID: paymentID) else { return }
            state.registerPresentationReset { [presentation] in presentation.payments.reset() }
            presentation.present(intent: intent, isDemo: state.isDemo) { outcome in
                Task { await state.finishSDK(outcome, attempt: attempt, paymentID: paymentID) }
            }
        }
    }
}

#if DEBUG
private struct DemoPaymentOutcomeSheet: View {
    @Bindable var state: PaymentsState
    let paymentID: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Demo checkout · no money moves").font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Text("These sample results do not open a payment SDK or contact a server.").foregroundStyle(Color.swMuted)
                    choice("Preview confirmed payment", scenario: .paid)
                    choice("Preview waiting for confirmation", scenario: .pending)
                    choice("Preview failed checkout", scenario: .failed)
                    choice("Preview canceled checkout", scenario: .cancelled)
                }.padding(24).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("demo-payment-outcome-scroll")
                .background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
                .navigationTitle("Demo checkout").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } } }
        }.presentationDetents([.large]).tint(Color.swAccentInk)
    }
    private func choice(_ title: LocalizedStringKey, scenario: DemoPaymentScenario) -> some View {
        Button {
            dismiss()
            Task { await state.simulateDemo(paymentID: paymentID, scenario: scenario) }
        } label: {
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
        }.buttonStyle(SWPrimary())
    }
}
#endif

struct PaymentDocumentsView: View {
    @Bindable var state: PaymentsState
    var paymentID: Int?
    @State private var share = false
    private var documents: [Components.Schemas.PaymentDocument] {
        state.documents.filter { paymentID == nil || $0.payment == paymentID }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Receipts and credit notes").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Open or share documents issued by your makerspace.").foregroundStyle(Color.swMuted)
                if state.isDemo { Text("Demo documents · sample data").foregroundStyle(Color.swMuted) }
                if case .loading = state.documentsLoad { ProgressView("Loading documents…") }
                if case .failed(let message) = state.documentsLoad {
                    SWError(message: message)
                    Button("Try again") { Task { await state.loadDocuments() } }.frame(minHeight: 48).disabled(!state.canRequest)
                }
                if state.documentsLoad == .ready && documents.isEmpty {
                    Text(paymentID != nil && state.documentsHaveMore ? "No matching documents on the loaded pages. Load more to continue." : "No issued documents yet.").foregroundStyle(Color.swMuted)
                }
                if let error = state.documentError { SWError(message: error) }
                if state.documentBusy { ProgressView("Preparing document…") }
                ForEach(documents, id: \.id) { document in
                    SWCard {
                        Text(document.kind.rawValue == "credit_note" ? "Credit note \(document.number)" : "Receipt \(document.number)").font(.headline)
                        PaymentMoney(amount: document.amount, currency: document.currency)
                        Text(document.issued_at, format: .dateTime.day().month().year()).foregroundStyle(Color.swMuted)
                        Button("Open PDF") { Task { await state.openDocument(document) } }.frame(minHeight: 48)
                            .disabled(state.documentBusy || !state.canRequest).accessibilityIdentifier("document-\(document.id)")
                    }
                }
                if state.documentsHaveMore {
                    Button("Load more documents") { Task { await state.loadDocuments(more: true) } }.frame(minHeight: 48)
                        .disabled(state.documentsLoad == .loading || !state.canRequest)
                }
            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("Documents").navigationBarTitleDisplayMode(.inline)
            .task { if state.documentsLoad == .idle { await state.loadDocuments() } }
            .refreshable { await state.loadDocuments() }
            .onChange(of: state.preview?.id) { _, _ in share = false }
            .sheet(item: $state.preview) { file in
                NavigationStack {
                    NativeDocumentPreview(file: file).navigationTitle("Payment document").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { state.preview = nil } }
                            ToolbarItem(placement: .primaryAction) { Button("Share", systemImage: "square.and.arrow.up") { share = true } }
                        }
                        .sheet(isPresented: $share) { NativeDocumentShare(file: file) }
                }
            }
    }
}

private struct PaymentMoney: View {
    let amount: String
    let currency: String
    var body: some View { Text("\(currency.uppercased()) \(amount)").monospacedDigit().foregroundStyle(Color.swInk) }
}
enum PaymentCopy {
    static func status(_ raw: String?) -> String {
        switch raw {
        case "pending": return String(localized: "Payment pending")
        case "paid_online": return String(localized: "Paid online")
        case "paid_offline": return String(localized: "Paid at the desk")
        case "waived": return String(localized: "Charge waived")
        case "canceled": return String(localized: "Canceled")
        default: return String(localized: "Status unavailable")
        }
    }
}

@MainActor @Observable private final class PaymentPresentationContext {
    @ObservationIgnored weak var anchor: UIViewController?
    let payments = NativePayments()
    func present(intent: Components.Schemas.MobilePaymentIntentResponse, isDemo: Bool,
                 completion: @escaping (NativePaymentOutcome) -> Void) {
        guard var controller = anchor, controller.viewIfLoaded?.window != nil else {
            completion(.unavailable("Checkout is not ready. Try again from payment details.")); return
        }
        while let parent = controller.parent { controller = parent }
        // Current contract is Stripe-specific. No vendor inference or Razorpay field synthesis.
        payments.presentStripe(clientSecret: intent.client_secret, publishableKey: intent.publishable_key,
            customerID: intent.customer_id.flatMap { $0 }, ephemeralKey: intent.ephemeral_key.flatMap { $0 },
            returnURL: URL(string: "spaceworks://payments/return"), isDemo: isDemo, from: controller, completion: completion)
    }
}
private struct PaymentPresentationAnchor: UIViewControllerRepresentable {
    let context: PaymentPresentationContext
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController(); self.context.anchor = controller; return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { self.context.anchor = controller }
}
