import Foundation
import SpaceWorksAPI
import XCTest
@testable import SpaceWorks

private enum PaymentFixture {
    static func decode<T: Decodable>(_ value: String) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(value.utf8))
    }
    static func row(status: String = "pending", online: Bool = true) throws -> Components.Schemas.MemberPayment {
        try decode(rowJSON(status: status, online: online))
    }
    static func rowJSON(status: String = "pending", online: Bool = true) -> String {
        """
        {"id":501,"subject_type":"loan_deposit","subject_label":"Equipment deposit","status":"\(status)","amount":"250.00",
        "currency":"inr","due_at":null,"due_date":"2026-10-20","due_state":"upcoming","checkout_url":"",
        "online_payment_available":\(online),"settlement":null,"refunded_amount":0,"refunds":[],"created_at":"2026-10-16T09:00:00Z"}
        """
    }
    static let documents = #"{"count":0,"next":null,"previous":null,"results":[]}"#
    static func intent(id: Int = 501) throws -> Components.Schemas.MobilePaymentIntentResponse {
        try decode("{\"payment_id\":\(id),\"client_secret\":\"pi_fixture_secret_test\",\"publishable_key\":\"pk_test_fixture\"}")
    }
}

private actor PaymentTestRepository: PaymentRepository {
    var rows: [Components.Schemas.MemberPayment]
    var intentID = 501
    var failure: APIError?
    private var offline = false
    private(set) var listCalls = 0
    private(set) var intentCalls = 0
    private(set) var documentCalls = 0
    private(set) var requestedPages: [Int] = []
    private var pages: [Int: Components.Schemas.DocumentPage] = [:]
    init(status: String = "pending", online: Bool = true) throws { rows = [try PaymentFixture.row(status: status, online: online)] }
    func configure(status: String) throws { rows = [try PaymentFixture.row(status: status)] }
    func configure(intentID: Int) { self.intentID = intentID }
    func configure(failure: APIError) { self.failure = failure }
    func configureOffline() { offline = true }
    func clearFailure() { failure = nil; offline = false }
    func configureDocuments(page: Int, json: String) throws {
        let value: Components.Schemas.DocumentPage = try PaymentFixture.decode(json)
        pages[page] = value
    }
    func payments() async throws -> [Components.Schemas.MemberPayment] {
        listCalls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        if let failure { throw failure }
        return rows
    }
    func intent(paymentID: Int) async throws -> Components.Schemas.MobilePaymentIntentResponse {
        intentCalls += 1; return try PaymentFixture.intent(id: intentID)
    }
    func documents(page: Int) async throws -> Components.Schemas.DocumentPage {
        documentCalls += 1; requestedPages.append(page)
        if let failure { throw failure }
        return try pages[page] ?? PaymentFixture.decode(PaymentFixture.documents)
    }
    func documentPDF(documentID: Int) async throws -> Data { Data("%PDF-fixture".utf8) }
}

@MainActor final class PaymentsTests: XCTestCase {
    func testPaymentLinkRefetchesAndOpensOnlyAnActualConfirmedRecord() async throws {
        let repository = try PaymentTestRepository(); let state = PaymentsState(repository: repository)
        let navigation = MemberNavigation()
        try await PaymentsLinkDestination.open(501, state: state, navigation: navigation) { true }
        XCTAssertEqual(navigation.selected, .profile); XCTAssertEqual(navigation.paths[.profile], [.payment(501)])
        let calls = await repository.listCalls; XCTAssertEqual(calls, 1)
    }
    func testMissingFailedAndReplacedPaymentLinkCannotNavigateUsingCachedRows() async throws {
        let repository = try PaymentTestRepository(); let state = PaymentsState(repository: repository)
        let navigation = MemberNavigation()
        await state.refresh()
        do { try await PaymentsLinkDestination.open(999, state: state, navigation: navigation) { true }; XCTFail("Unknown charge opened") }
        catch { XCTAssertEqual(APIError.status(error), 404) }
        await repository.configure(failure: APIError(status: 503, code: "offline", detail: "Try later."))
        do { try await PaymentsLinkDestination.open(501, state: state, navigation: navigation) { true }; XCTFail("Cached charge opened after refusal") }
        catch { XCTAssertEqual(APIError.display(error), "Try later.") }
        var checks = 0
        do { try await PaymentsLinkDestination.open(501, state: state, navigation: navigation) { checks += 1; return checks < 2 }; XCTFail("Replaced link opened") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(navigation.selected, .home); XCTAssertTrue(navigation.paths.isEmpty)
    }
    func testConcurrentForbiddenReadClearsCheckoutBeforeSDKResetAndRejectsItsLateCallback() async throws {
        let repository = try PaymentTestRepository(); let state = PaymentsState(repository: repository)
        await state.refresh(); let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        var resets = 0; state.registerPresentationReset { resets += 1 }
        await repository.configure(failure: APIError(status: 403, code: "forbidden", detail: "Payments are unavailable."))
        await state.loadDocuments()
        XCTAssertEqual(resets, 1); XCTAssertEqual(state.checkout, .idle)
        XCTAssertTrue(state.records.isEmpty); XCTAssertTrue(state.documents.isEmpty); XCTAssertNil(state.preview)
        XCTAssertEqual(state.load, .failed("Payments are unavailable."))
        let before = await repository.listCalls
        await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501)
        let after = await repository.listCalls; XCTAssertEqual(before, after)
    }
    func testSubmittedPaymentWithOfflineStatusReadCannotStartAnotherIntentAndFreshPaidReadCompletes() async throws {
        let repository = try PaymentTestRepository(); let state = PaymentsState(repository: repository, sleep: { _ in })
        await state.refresh(); let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        await repository.configureOffline()
        await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501)
        XCTAssertEqual(state.checkout, .awaiting(501)); XCTAssertNotNil(state.reconciliationError)
        XCTAssertFalse(state.canPay(try XCTUnwrap(state.record(501))))
        let next = await state.prepareCheckout(paymentID: 501); XCTAssertNil(next)
        let intents = await repository.intentCalls; XCTAssertEqual(intents, 1)
        await repository.clearFailure(); try await repository.configure(status: "paid_online")
        await state.refresh(); XCTAssertEqual(state.checkout, .completed(501)); XCTAssertNil(state.reconciliationError)
    }
    func testCancelledOrFailedSDKWithOfflineReadRequiresFreshServerStatusBeforeAnotherCheckout() async throws {
        for outcome in [NativePaymentOutcome.cancelled, .failed("Checkout failed.")] {
            let repository = try PaymentTestRepository(); let state = PaymentsState(repository: repository)
            await state.refresh(); let prepared = await state.prepareCheckout(paymentID: 501)
            let (attempt, _) = try XCTUnwrap(prepared)
            await repository.configureOffline(); await state.finishSDK(outcome, attempt: attempt, paymentID: 501)
            XCTAssertTrue(state.requiresStatusRefresh(501)); XCTAssertFalse(state.canPay(try XCTUnwrap(state.record(501))))
            let retry = await state.prepareCheckout(paymentID: 501); XCTAssertNil(retry)
            let intents = await repository.intentCalls; XCTAssertEqual(intents, 1)
            await repository.clearFailure(); await state.refresh()
            XCTAssertFalse(state.requiresStatusRefresh(501)); XCTAssertTrue(state.canPay(try XCTUnwrap(state.record(501))))
            XCTAssertEqual(state.record(501)?.status?.rawValue, "pending")
        }
    }
    func testConcurrentDocumentThrottleStopsNextSubmittedPaymentPollUntilDeadline() async throws {
        let repository = try PaymentTestRepository(); let gate = PaymentPollGate()
        let state = PaymentsState(repository: repository, sleep: { _ in await gate.arrive() })
        await state.refresh(); let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        let checking = Task { await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501) }
        await gate.entered()
        let before = await repository.listCalls
        await repository.configure(failure: APIError(status: 429, code: "throttled", detail: "Wait before trying again.", retryAfter: Date().addingTimeInterval(60)))
        await state.loadDocuments(); XCTAssertFalse(state.canRequest)
        await gate.release(); await checking.value
        let after = await repository.listCalls
        XCTAssertEqual(before, after); XCTAssertEqual(state.checkout, .awaiting(501))
        XCTAssertFalse(state.canPay(try XCTUnwrap(state.record(501))))
        XCTAssertEqual(state.reconciliationError, "Wait before trying again."); state.invalidate()
    }
    func testSDKSuccessNeverMarksPendingPaymentPaid() async throws {
        let repository = try PaymentTestRepository()
        let state = PaymentsState(repository: repository, sleep: { _ in })
        await state.refresh()
        let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501)
        XCTAssertEqual(state.checkout, .awaiting(501))
        XCTAssertEqual(state.record(501)?.status?.rawValue, "pending")
        let polls = await repository.listCalls
        XCTAssertEqual(polls, 6) // Initial load, fresh checkout authorization, four bounded reconciliation reads.
        XCTAssertFalse(state.canPay(try XCTUnwrap(state.record(501))))
    }
    func testServerPaidStatusWinsEvenWhenSDKReportsCancellation() async throws {
        let repository = try PaymentTestRepository()
        let state = PaymentsState(repository: repository, sleep: { _ in })
        await state.refresh()
        let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        try await repository.configure(status: "paid_online")
        await state.finishSDK(.cancelled, attempt: attempt, paymentID: 501)
        XCTAssertEqual(state.checkout, .completed(501))
        XCTAssertEqual(state.record(501)?.status?.rawValue, "paid_online")
        let documentCalls = await repository.documentCalls
        XCTAssertEqual(documentCalls, 1)
    }
    func testPullToRefreshReplacesAwaitingNoticeAfterAuthoritativePaymentConfirmation() async throws {
        let repository = try PaymentTestRepository()
        let state = PaymentsState(repository: repository, sleep: { _ in })
        await state.refresh()
        let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501)
        XCTAssertEqual(state.checkout, .awaiting(501))
        try await repository.configure(status: "paid_online")
        await state.refresh()
        XCTAssertEqual(state.checkout, .completed(501))
        let documents = await repository.documentCalls
        XCTAssertEqual(documents, 1)
    }
    func testDocumentsFollowActualNextPageAndMergeDuplicateIDsOnlyOnce() async throws {
        let repository = try PaymentTestRepository()
        let first = #"{"id":901,"payment":501,"number":"R1","kind":"receipt","issued_at":"2026-10-16T09:00:00Z","money_at":"2026-10-16T09:00:00Z","amount":"250.00","currency":"inr"}"#
        let second = first.replacingOccurrences(of: "901", with: "902")
        try await repository.configureDocuments(page: 1, json: "{\"count\":2,\"next\":\"https://spaceworks.example/api/v1/member/makerspaces/7/payment-documents?page=3\",\"previous\":null,\"results\":[\(first)]}")
        try await repository.configureDocuments(page: 3, json: "{\"count\":2,\"next\":null,\"previous\":null,\"results\":[\(first),\(second)]}")
        let state = PaymentsState(repository: repository)
        await state.loadDocuments()
        await state.loadDocuments(more: true)
        let pages = await repository.requestedPages
        XCTAssertEqual(pages, [1, 3])
        XCTAssertEqual(state.documents.map(\.id), [901, 902])
        XCTAssertFalse(state.documentsHaveMore)
    }
    func testNewServerStatusPreventsLaunchingAnOutdatedCharge() async throws {
        let repository = try PaymentTestRepository()
        let state = PaymentsState(repository: repository, sleep: { _ in })
        await state.refresh()
        try await repository.configure(status: "waived")
        let result = await state.prepareCheckout(paymentID: 501)
        XCTAssertNil(result)
        XCTAssertEqual(state.record(501)?.status?.rawValue, "waived")
        let intents = await repository.intentCalls
        XCTAssertEqual(intents, 0)
    }
    func testOfflineOnlyChargeAndMismatchedIntentNeverReachSDK() async throws {
        let offline = try PaymentTestRepository(online: false)
        let offlineState = PaymentsState(repository: offline)
        await offlineState.refresh()
        let unavailable = await offlineState.prepareCheckout(paymentID: 501)
        XCTAssertNil(unavailable)
        let offlineIntents = await offline.intentCalls
        XCTAssertEqual(offlineIntents, 0)
        let repository = try PaymentTestRepository()
        await repository.configure(intentID: 999)
        let state = PaymentsState(repository: repository)
        await state.refresh()
        let wrongPayment = await state.prepareCheckout(paymentID: 501)
        XCTAssertNil(wrongPayment)
        XCTAssertFalse(state.busy)
    }
    func testLogoutClearsPaymentDataResetsSDKAndRejectsLateCallback() async throws {
        let repository = try PaymentTestRepository()
        var reset = false
        let state = PaymentsState(repository: repository, sleep: { _ in })
        state.registerPresentationReset { reset = true }
        await state.refresh()
        let prepared = await state.prepareCheckout(paymentID: 501)
        let (attempt, _) = try XCTUnwrap(prepared)
        state.invalidate()
        await state.finishSDK(.awaitingServerConfirmation, attempt: attempt, paymentID: 501)
        XCTAssertTrue(reset)
        XCTAssertTrue(state.records.isEmpty)
        XCTAssertTrue(state.documents.isEmpty)
        XCTAssertEqual(state.checkout, .idle)
    }
    func testUnauthorizedReadClearsScopeAndReturnsToAuthentication() async throws {
        let repository = try PaymentTestRepository()
        var signedOut = 0
        let state = PaymentsState(repository: repository, onUnauthorized: { signedOut += 1 })
        await state.refresh()
        await repository.configure(failure: APIError(status: 401, code: "session_expired", detail: "Expired"))
        await state.refresh()
        XCTAssertEqual(signedOut, 1)
        XCTAssertTrue(state.records.isEmpty)
    }
    func testRetryAfterPreventsRepeatedCheckoutAndStatusRequestsUntilCooldown() async throws {
        let repository = try PaymentTestRepository()
        let state = PaymentsState(repository: repository)
        await state.refresh()
        await repository.configure(failure: APIError(status: 429, code: "throttled", detail: "Please wait.", retryAfter: Date().addingTimeInterval(60)))
        let result = await state.prepareCheckout(paymentID: 501)
        XCTAssertNil(result)
        XCTAssertFalse(state.canRequest)
        let requestsBefore = await repository.listCalls
        await state.refresh()
        await state.checkStatus(paymentID: 501)
        await state.loadDocuments()
        let requestsAfter = await repository.listCalls
        let documentsAfter = await repository.documentCalls
        XCTAssertEqual(requestsBefore, requestsAfter)
        XCTAssertEqual(documentsAfter, 0)
        state.invalidate()
    }
    #if DEBUG
    func testDemoPaymentRecordsRemainSeparateAcrossMakerspaceSwitchAndResetWithDemoSession() async throws {
        let session = DemoSession(); let first = session.paymentRepository(for: 7); let second = session.paymentRepository(for: 8)
        await first.simulate(paymentID: 501, scenario: .paid)
        let firstRows = try await session.paymentRepository(for: 7).payments()
        let secondRows = try await second.payments()
        XCTAssertEqual(firstRows.first?.status?.rawValue, "paid_online"); XCTAssertEqual(secondRows.first?.status?.rawValue, "pending")
        session.reset()
        let reset = try await session.paymentRepository(for: 7).payments(); XCTAssertEqual(reset.first?.status?.rawValue, "pending")
    }
    func testDemoPaymentsUseIsolatedFixtureAndNeverRequestAnSDKIntent() async throws {
        let state = PaymentsState(repository: DemoPaymentRepository(), isDemo: true, sleep: { _ in })
        await state.refresh()
        let actualIntent = await state.prepareCheckout(paymentID: 501)
        XCTAssertNil(actualIntent)
        await state.simulateDemo(paymentID: 501, scenario: .paid)
        XCTAssertEqual(state.checkout, .completed(501))
        XCTAssertEqual(state.record(501)?.status?.rawValue, "paid_online")
        XCTAssertTrue(state.documents.contains { $0.payment == 501 })
        if let document = state.documents.first {
            await state.openDocument(document)
            XCTAssertNotNil(state.preview)
            state.invalidate()
            XCTAssertNil(state.preview)
        }
    }
    #endif
}

final class PaymentOperationTests: XCTestCase {
    private let origin = try! ServerOrigin("https://spaceworks.example")
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func service(_ handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)) async throws -> SpaceWorksService {
        StubProtocol.lock.lock(); StubProtocol.handler = handler; StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: configuration),
                                       initialTokens: TokenPair(access: "fixture-access", refresh: "fixture-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7])
        return service
    }
    private func assertScoped(_ request: URLRequest) {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
        for name in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: name)) }
    }
    func testPaymentListIsGeneratedArrayAndIntentUsesExactDocumentedPOST() async throws {
        let service = try await service { request in
            self.assertScoped(request)
            if request.url?.path == "/api/v1/member/makerspaces/7/payments" {
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, ["Content-Type": "application/json"], Data("[\(PaymentFixture.rowJSON())]".utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/v1/member/makerspaces/7/payments/501/mobile-intent")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(requestBody(request).isEmpty)
            return (200, ["Content-Type": "application/json"], Data(#"{"payment_id":501,"client_secret":"pi_fixture_secret_test","publishable_key":"pk_test_fixture"}"#.utf8))
        }
        let rows = try await service.memberPayments(makerspaceID: 7)
        XCTAssertEqual(rows.first?.id, 501)
        let intent = try await service.memberPaymentIntent(makerspaceID: 7, paymentID: 501)
        XCTAssertEqual(intent.payment_id, 501)
    }
    func testDocumentListUsesGeneratedPagingAndPDFRetainsRequiredAPIAuthentication() async throws {
        let service = try await service { request in
            self.assertScoped(request)
            let path = try XCTUnwrap(request.url?.path)
            if path.hasSuffix("/payment-documents") {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems?.first?.value, "2")
                return (200, ["Content-Type": "application/json"], Data(PaymentFixture.documents.utf8))
            }
            if path.hasSuffix("/download-url") {
                XCTAssertEqual(path, "/api/v1/member/makerspaces/7/payment-documents/901/download-url")
                return (200, ["Content-Type": "application/json"], Data(#"{"url":"/api/v1/payment-documents/901/download?token=short-lived","expires_in":300}"#.utf8))
            }
            XCTAssertEqual(path, "/api/v1/payment-documents/901/download")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems?.first?.value, "short-lived")
            return (200, ["Content-Type": "application/pdf"], Data("%PDF-fixture".utf8))
        }
        _ = try await service.memberPaymentDocuments(makerspaceID: 7, page: 2)
        let bytes = try await service.memberPaymentPDF(makerspaceID: 7, documentID: 901, origin: origin)
        XCTAssertTrue(bytes.starts(with: Data("%PDF-".utf8)))
    }
    func testDownloadGrantRejectsExternalWrongResourceAndAmbiguousQueryBeforeAnyAuthenticatedFetch() throws {
        let token = try PaymentDownloadGrant.token(from: "/api/v1/payment-documents/901/download?token=valid", documentID: 901, origin: origin)
        XCTAssertEqual(token, "valid")
        XCTAssertEqual(try PaymentDownloadGrant.token(from: "https://spaceworks.example:443/api/v1/payment-documents/901/download?token=valid", documentID: 901, origin: origin), "valid")
        XCTAssertEqual(try PaymentDownloadGrant.token(from: "https://spaceworks.example/api/v1/payment-documents/901/download?token=valid", documentID: 901,
            origin: ServerOrigin("https://spaceworks.example:443")), "valid")
        for value in ["https://evil.example/api/v1/payment-documents/901/download?token=x",
                      "http://spaceworks.example/api/v1/payment-documents/901/download?token=x",
                      "https://user:pass@spaceworks.example/api/v1/payment-documents/901/download?token=x",
                      "/api/v1/payment-documents/902/download?token=x", "/api/v1/payment-documents/901/download?token=x&token=y",
                      "/api/v1/payment-documents/901/download?token=x#fragment", "/api/v1/payment-documents/901/download?token=",
                      "/api/v1/payment-documents/901/%2E%2E/download?token=x"] {
            XCTAssertThrowsError(try PaymentDownloadGrant.token(from: value, documentID: 901, origin: origin), value)
        }
    }
    func testWrappedCancellationAfterLocalTokenWipeDoesNotTriggerAnotherAccountLogout() async throws {
        let callbacks = PaymentRequestCounter()
        let service = try await service { _ in throw URLError(.cancelled) }
        let credentials = await service.refresh.snapshot()
        try await service.refresh.install(nil)
        let repository = LivePaymentRepository(service: service, expectedCredentials: credentials, makerspaceID: 7, origin: origin, onUnauthorized: { _ in callbacks.increment() })
        do { _ = try await repository.payments(); XCTFail("Expected cancelled transport") }
        catch { XCTAssertTrue(PaymentOperationFailure.isCancellation(error)) }
        XCTAssertEqual(callbacks.value, 0)
    }
    func testInvalidGrantNeverMakesSecondRequestToItsTarget() async throws {
        let count = PaymentRequestCounter()
        let service = try await service { request in
            count.increment(); self.assertScoped(request)
            XCTAssertTrue(request.url!.path.hasSuffix("/download-url"))
            return (200, ["Content-Type": "application/json"], Data(#"{"url":"https://evil.example/download?token=secret","expires_in":300}"#.utf8))
        }
        do { _ = try await service.memberPaymentPDF(makerspaceID: 7, documentID: 901, origin: origin); XCTFail("Invalid grant accepted") }
        catch { XCTAssertEqual(APIError.code(error), "invalid_document_grant") }
        XCTAssertEqual(count.value, 1)
    }
}

private final class PaymentRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private actor PaymentPollGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func arrive() async { started = true; observer?.resume(); observer = nil; await withCheckedContinuation { continuation = $0 } }
    func entered() async { if !started { await withCheckedContinuation { observer = $0 } } }
    func release() { continuation?.resume(); continuation = nil }
}
