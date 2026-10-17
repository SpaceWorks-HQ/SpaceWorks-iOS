import Foundation
import Observation
import SpaceWorksAPI

protocol PaymentRepository: Sendable {
    func payments() async throws -> [Components.Schemas.MemberPayment]
    func intent(paymentID: Int) async throws -> Components.Schemas.MobilePaymentIntentResponse
    func documents(page: Int) async throws -> Components.Schemas.DocumentPage
    func documentPDF(documentID: Int) async throws -> Data
}

struct LivePaymentRepository: PaymentRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot?
    let makerspaceID: Int
    let origin: ServerOrigin
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }
    var onForbidden: @Sendable () async -> Void = {}
    private func checked<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard let expectedCredentials, await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        do { return try await service.withMakerspace(makerspaceID, expectedCredentials: expectedCredentials, operation: work) }
        catch {
            if Task.isCancelled || APIError.isCancellation(error) { throw error }
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            let empty = await service.refresh.current() == nil
            if APIError.status(error) == 401 || empty { await onUnauthorized(APIError.display(error)) }
            else if APIError.status(error) == 403 { await onForbidden() }
            throw error
        }
    }
    func payments() async throws -> [Components.Schemas.MemberPayment] {
        try await checked { try await service.memberPayments(makerspaceID: makerspaceID) }
    }
    func intent(paymentID: Int) async throws -> Components.Schemas.MobilePaymentIntentResponse {
        try await checked { try await service.memberPaymentIntent(makerspaceID: makerspaceID, paymentID: paymentID) }
    }
    func documents(page: Int) async throws -> Components.Schemas.DocumentPage {
        let result = try await checked { try await service.memberPaymentDocuments(makerspaceID: makerspaceID, page: page) }
        if let next = try origin.nextPage(result.next), next.path != "/api/v1/member/makerspaces/\(makerspaceID)/payment-documents" {
            throw APIError(status: 0, code: "invalid_next_page", detail: String(localized: "The next document page is unavailable. Refresh and try again."))
        }
        return result
    }
    func documentPDF(documentID: Int) async throws -> Data {
        try await checked { try await service.memberPaymentPDF(makerspaceID: makerspaceID, documentID: documentID, origin: origin) }
    }
}

@MainActor @Observable
final class PaymentsState {
    enum Load: Equatable { case idle, loading, ready, failed(String) }
    enum Checkout: Equatable {
        case idle, preparing(Int), presenting(Int), checking(Int), awaiting(Int), completed(Int), stopped(Int, String)
    }
    let isDemo: Bool
    private let repository: any PaymentRepository
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let onUnauthorized: () -> Void
    private let cancelSDK: () -> Void
    private var cancelPresentation: (() -> Void)?
    private var active = true
    private var listGeneration = 0
    private var documentGeneration = 0
    private var previewGeneration = 0
    private var nextDocumentPage: Int?
    private var checkoutAttempt: UUID?
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    private(set) var retryAfter = Date.distantPast
    private(set) var records: [Components.Schemas.MemberPayment] = []
    private(set) var documents: [Components.Schemas.PaymentDocument] = []
    private(set) var load = Load.idle
    private(set) var documentsLoad = Load.idle
    private(set) var checkout = Checkout.idle
    private(set) var reconciliationError: String?
    private var throttleMessage: String?
    private var needsFreshStatus = Set<Int>()
    var documentsHaveMore: Bool { nextDocumentPage != nil }
    private(set) var documentBusy = false
    private(set) var documentError: String?
    var preview: NativeDocumentFile?

    init(repository: any PaymentRepository, isDemo: Bool = false,
         sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         onUnauthorized: @escaping () -> Void = {}, cancelSDK: @escaping () -> Void = {}) {
        self.repository = repository; self.isDemo = isDemo; self.sleep = sleep
        self.onUnauthorized = onUnauthorized; self.cancelSDK = cancelSDK
    }
    var busy: Bool {
        switch checkout { case .preparing, .presenting, .checking: return true; default: return false }
    }
    var canRequest: Bool { active && Date() >= retryAfter }
    func record(_ id: Int) -> Components.Schemas.MemberPayment? { records.first { $0.id == id } }
    func requiresStatusRefresh(_ id: Int) -> Bool { needsFreshStatus.contains(id) }
    func canPay(_ row: Components.Schemas.MemberPayment) -> Bool {
        canRequest && !busy && !needsFreshStatus.contains(row.id) && row.status?.rawValue == "pending" && row.online_payment_available && checkout != .awaiting(row.id)
    }
    func invalidate() {
        active = false; listGeneration += 1; documentGeneration += 1; previewGeneration += 1
        cooldownTask?.cancel(); cooldownTask = nil
        checkoutAttempt = nil; cancelSDK(); cancelPresentation?(); cancelPresentation = nil
        records = []; documents = []; preview = nil; nextDocumentPage = nil; needsFreshStatus = []
        documentBusy = false; documentError = nil; reconciliationError = nil; throttleMessage = nil; checkout = .idle
    }
    func registerPresentationReset(_ reset: @escaping () -> Void) {
        guard active else { reset(); return }
        cancelPresentation?()
        cancelPresentation = reset
    }
    #if DEBUG
    func simulateDemo(paymentID: Int, scenario: DemoPaymentScenario) async {
        guard active, isDemo, !busy, let demo = repository as? any DemoPaymentControlling,
              let row = record(paymentID), canPay(row) else { return }
        let attempt = UUID(); checkoutAttempt = attempt; checkout = .presenting(paymentID)
        await demo.simulate(paymentID: paymentID, scenario: scenario)
        await finishSDK(scenario.outcome, attempt: attempt, paymentID: paymentID)
    }
    func simulateDelayedConfirmation(paymentID: Int) async {
        guard active, isDemo, !busy, checkout == .awaiting(paymentID),
              let demo = repository as? any DemoPaymentControlling else { return }
        await demo.simulate(paymentID: paymentID, scenario: .paid)
        await checkStatus(paymentID: paymentID)
    }
    #endif
    func refresh() async {
        guard canRequest, !busy else { return }
        listGeneration += 1; let generation = listGeneration
        load = .loading
        do {
            let result = try await repository.payments()
            guard active, generation == listGeneration else { return }
            records = result; load = .ready; needsFreshStatus.subtract(result.map(\.id))
            if reconcileVisibleCheckout() { await loadDocuments() }
        } catch {
            guard active, generation == listGeneration else { return }
            failAuthorization(error)
            if active { load = .failed(APIError.display(error)) }
        }
    }
    /// Fresh server data and a fresh documented intent precede every explicit SDK launch.
    func prepareCheckout(paymentID: Int) async -> (UUID, Components.Schemas.MobilePaymentIntentResponse)? {
        guard active, !isDemo, !busy, let initial = record(paymentID), canPay(initial) else { return nil }
        listGeneration += 1 // An older pull-to-refresh cannot overwrite this checkout's fresh result.
        let attempt = UUID(); checkoutAttempt = attempt; reconciliationError = nil; checkout = .preparing(paymentID)
        do {
            let current = try await repository.payments()
            guard matches(attempt) else { return nil }
            records = current
            guard let row = record(paymentID), row.status?.rawValue == "pending", row.online_payment_available else {
                checkoutAttempt = nil; checkout = .stopped(paymentID, "This payment is no longer available to pay online. Its latest status is shown above.")
                return nil
            }
            guard canRequest else { throw throttledCheckout }
            let intent = try await repository.intent(paymentID: paymentID)
            guard matches(attempt) else { return nil }
            guard canRequest else { throw throttledCheckout }
            guard intent.payment_id == paymentID, !intent.client_secret.isEmpty, !intent.publishable_key.isEmpty else {
                throw APIError(status: 0, code: "invalid_payment_setup", detail: String(localized: "Payment setup is unavailable. Contact your makerspace."))
            }
            checkout = .presenting(paymentID)
            return (attempt, intent)
        } catch {
            guard matches(attempt) else { return nil }
            checkoutAttempt = nil; failAuthorization(error)
            if active { checkout = .stopped(paymentID, APIError.display(error)) }
            return nil
        }
    }
    func finishSDK(_ outcome: NativePaymentOutcome, attempt: UUID, paymentID: Int) async {
        guard matches(attempt), checkout == .presenting(paymentID) else { return }
        needsFreshStatus.insert(paymentID); checkout = .checking(paymentID)
        await reconcile(paymentID: paymentID, attempt: attempt, outcome: outcome)
    }
    func checkStatus(paymentID: Int) async {
        guard canRequest, !busy else { return }
        listGeneration += 1
        let attempt = UUID(); checkoutAttempt = attempt; reconciliationError = nil; checkout = .checking(paymentID)
        await reconcile(paymentID: paymentID, attempt: attempt, outcome: .awaitingServerConfirmation)
    }
    private func reconcile(paymentID: Int, attempt: UUID, outcome: NativePaymentOutcome) async {
        let tries = outcome == .awaitingServerConfirmation ? 4 : 1
        do {
            for index in 0..<tries {
                if index > 0 { try await sleep(UInt64(index) * 1_000_000_000) }
                guard matches(attempt) else { return }
                guard canRequest else {
                    needsFreshStatus.insert(paymentID)
                    checkoutAttempt = nil; reconciliationError = throttleMessage ?? String(localized: "Too many requests. Try again later.")
                    checkout = outcome == .awaitingServerConfirmation ? .awaiting(paymentID) : .stopped(paymentID, reconciliationError!)
                    return
                }
                let result = try await repository.payments()
                guard matches(attempt) else { return }
                records = result; load = .ready; needsFreshStatus.remove(paymentID)
                if let row = record(paymentID), ["paid_online", "paid_offline", "waived"].contains(row.status?.rawValue ?? "") {
                    checkoutAttempt = nil; checkout = .completed(paymentID)
                    await loadDocuments(); return
                }
                if record(paymentID)?.status?.rawValue == "canceled" {
                    checkoutAttempt = nil; checkout = .stopped(paymentID, "This payment was canceled."); return
                }
            }
            guard matches(attempt) else { return }
            checkoutAttempt = nil
            switch outcome {
            case .awaitingServerConfirmation: checkout = .awaiting(paymentID)
            case .cancelled: checkout = .stopped(paymentID, "Checkout closed. Check the current payment status before trying again.")
            case .failed(let message), .unavailable(let message): checkout = .stopped(paymentID, message)
            }
        } catch {
            guard matches(attempt) else { return }
            checkoutAttempt = nil; failAuthorization(error)
            guard active, APIError.status(error) != 403 else { return }
            needsFreshStatus.insert(paymentID); reconciliationError = APIError.display(error)
            // An SDK-submitted payment is still unknown when a status read fails. Never
            // offer another checkout until authoritative state confirms what happened.
            checkout = outcome == .awaitingServerConfirmation ? .awaiting(paymentID) : .stopped(paymentID, String(localized: "Couldn't check this payment. Refresh its status before trying again."))
        }
    }
    func loadDocuments(more: Bool = false) async {
        guard canRequest, !(more && (documentsLoad == .loading || !documentsHaveMore)) else { return }
        documentGeneration += 1; let generation = documentGeneration
        let page = more ? nextDocumentPage! : 1
        documentsLoad = .loading
        do {
            let result = try await repository.documents(page: page)
            guard active, generation == documentGeneration else { return }
            let next = try Self.nextDocumentPage(result.next, after: page)
            var merged = more ? documents : []
            for document in result.results {
                if let index = merged.firstIndex(where: { $0.id == document.id }) { merged[index] = document }
                else { merged.append(document) }
            }
            documents = merged; nextDocumentPage = next; documentsLoad = .ready
        } catch {
            guard active, generation == documentGeneration else { return }
            failAuthorization(error)
            if active { documentsLoad = .failed(APIError.display(error)) }
        }
    }
    func openDocument(_ document: Components.Schemas.PaymentDocument) async {
        guard canRequest, !documentBusy, documents.contains(where: { $0.id == document.id }) else { return }
        previewGeneration += 1; let generation = previewGeneration
        preview = nil; documentError = nil; documentBusy = true
        do {
            let data = try await repository.documentPDF(documentID: document.id)
            guard active, generation == previewGeneration else { return }
            preview = try NativeFileTransfer.document(data: data, kind: .pdf, suggestedName: document.number)
        } catch {
            guard active, generation == previewGeneration else { return }
            failAuthorization(error)
            if active { documentError = (error as? NativeTransferError)?.errorDescription ?? APIError.display(error) }
        }
        if active, generation == previewGeneration { documentBusy = false }
    }
    private func matches(_ attempt: UUID) -> Bool { active && checkoutAttempt == attempt }
    private func reconcileVisibleCheckout() -> Bool {
        let id: Int
        switch checkout {
        case .awaiting(let tracked), .stopped(let tracked, _), .completed(let tracked): id = tracked
        default: return false
        }
        guard let row = record(id) else { return false }
        if ["paid_online", "paid_offline", "waived"].contains(row.status?.rawValue ?? "") {
            checkout = .completed(id); reconciliationError = nil; return true
        }
        if row.status?.rawValue == "canceled" { checkout = .stopped(id, "This payment was canceled.") }
        return false
    }
    private static func nextDocumentPage(_ value: String?, after page: Int) throws -> Int? {
        guard let value else { return nil }
        guard let parts = URLComponents(string: value), let items = parts.queryItems,
              items.count == 1, items[0].name == "page", let raw = items[0].value,
              !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let next = Int(raw), next > page else {
            throw APIError(status: 0, code: "invalid_next_page", detail: String(localized: "The next document page is unavailable. Refresh and try again."))
        }
        return next
    }
    private var throttledCheckout: APIError { APIError(status: 429, code: "payment_throttled", detail: throttleMessage ?? String(localized: "Too many requests. Try again later."), retryAfter: retryAfter) }
    private func failAuthorization(_ error: Error) {
        if APIError.status(error) == 429 { throttleMessage = APIError.display(error) }
        if let deadline = APIError.retryDeadline(error), deadline > retryAfter {
            retryAfter = deadline
            cooldownTask?.cancel()
            cooldownTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let deadline = self?.retryAfter else { return }
                    let delay = deadline.timeIntervalSinceNow
                    if delay <= 0 { self?.retryAfter = .distantPast; return }
                    do { try await Task.sleep(nanoseconds: UInt64(min(60, delay) * 1_000_000_000)) }
                    catch { return }
                }
            }
        }
        if APIError.status(error) == 401 { invalidate(); onUnauthorized() }
        else if APIError.status(error) == 403 {
            // A concurrent document/read refusal also revokes any pending native checkout.
            // Clear its attempt before resetting the SDK so a late callback cannot reconcile.
            listGeneration += 1; documentGeneration += 1; previewGeneration += 1
            checkoutAttempt = nil; cancelSDK(); cancelPresentation?(); cancelPresentation = nil
            checkout = .idle; reconciliationError = nil; documentBusy = false; documentError = nil
            records = []; documents = []; preview = nil; nextDocumentPage = nil; needsFreshStatus = []
            load = .failed(APIError.display(error)); documentsLoad = .failed(APIError.display(error))
        }
    }
}
