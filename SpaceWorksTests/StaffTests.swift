import Foundation
import Observation
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

private enum StaffFixture {
    static let actions: Set<String> = ["accept_request", "reject_request", "assign_box", "issue_request", "return_request", "upload_evidence", "issue_direct_loan", "manage_events", "manage_bookings"]
    static func decode<T: Decodable>(_ value: String, changes: [String: Any] = [:]) throws -> T {
        var object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as! [String: Any]
        object.merge(changes) { _, new in new }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func page(_ json: String, extra: [String: Any] = [:]) throws -> String {
        var object: [String: Any] = ["count": 1, "next": NSNull(), "previous": NSNull(), "results": [try JSONSerialization.jsonObject(with: Data(json.utf8))]]
        object.merge(extra) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

private final class StaffObservationChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}

#if DEBUG
@MainActor final class StaffTests: XCTestCase {
    private func state(_ repository: DemoStaffRepository = DemoStaffRepository(), kits: Bool = false, actions: Set<String> = StaffFixture.actions) -> StaffState {
        StaffState(repository: repository, makerspaceID: 7, actions: actions, features: kits ? ["loans.kit_checklist"] : [])
    }
    private var photo: Data { Data([0xff, 0xd8, 0xff, 0xe0, 0, 1, 2]) }
    private func issue(_ parent: StaffState) async throws -> StaffHandoverState {
        parent.queue = .accepted; await parent.loadQueue()
        let row = try XCTUnwrap(parent.requests.first)
        let handover = StaffHandoverState(parent: parent, mode: .issue(row))
        await handover.scan("DEMO-BOX", box: true); handover.borrowerChecked = true
        handover.setPhoto(photo); await handover.uploadPhoto(); await handover.prepareKits()
        return handover
    }
    func testChildConstructionDoesNotInvalidateParentViewObservation() throws {
        let parent = state()
        let event: Components.Schemas.EventAdmin = try StaffFixture.decode(DebugStaffFixtures.event)
        let changes = StaffObservationChanges()
        let first = withObservationTracking {
            StaffCheckInState(parent: parent, event: event)
        } onChange: { changes.record() }
        let second = StaffCheckInState(parent: parent, event: event)
        XCTAssertEqual(changes.count, 0, "Registering cleanup must not rebuild a destination that constructs child state.")
        parent.invalidate()
        XCTAssertEqual(changes.count, 1, "Actual scope invalidation remains observable.")
        XCTAssertEqual(first.eventTitle, ""); XCTAssertEqual(second.eventTitle, "")
    }
    func testDemoStaffRowsMatchTheirActualSelectedMakerspace() async throws {
        let repository = DemoStaffRepository(makerspaceID: 8)
        let parent = StaffState(repository: repository, makerspaceID: 8, actions: StaffFixture.actions, features: [])
        await parent.loadQueue(); let row = try XCTUnwrap(parent.requests.first)
        XCTAssertEqual(row.makerspace_id, 8)
        await parent.accept(row, quantities: [61: 2]); XCTAssertNil(parent.error)
        parent.queue = .accepted; await parent.loadQueue()
        XCTAssertTrue(parent.requests.allSatisfy { $0.makerspace_id == 8 })
        for payload in ["DEMO-BOX", "DEMO-TOOL"] {
            let resolved = try await repository.resolveQR(body: .init(payload: payload))
            XCTAssertEqual(resolved.qr.makerspace, 8)
        }
    }
    func testAcceptMovesActualRequestIntoAcceptedQueue() async throws {
        let parent = state(); await parent.loadQueue(); let row = try XCTUnwrap(parent.requests.first)
        await parent.accept(row, quantities: [61: 2]); XCTAssertNil(parent.error); XCTAssertTrue(parent.requests.isEmpty)
        parent.queue = .accepted; await parent.loadQueue(); XCTAssertTrue(parent.requests.contains { $0.id == row.id })
    }
    func testPartialAcceptancePersistsThroughIssueAndQueueRefetch() async throws {
        let parent = state(); await parent.loadQueue(); let pending = try XCTUnwrap(parent.requests.first)
        XCTAssertEqual(pending.items.first?.accepted_quantity, 0); XCTAssertEqual(pending.items.first?.issued_quantity, 0)
        await parent.accept(pending, quantities: [61: 1]); XCTAssertNil(parent.error)
        parent.queue = .accepted; await parent.loadQueue()
        let accepted = try XCTUnwrap(parent.requests.first { $0.id == pending.id })
        XCTAssertEqual(accepted.items.first?.accepted_quantity, 1); XCTAssertEqual(accepted.items.first?.issued_quantity, 0)
        let handover = StaffHandoverState(parent: parent, mode: .issue(accepted))
        await handover.scan("DEMO-BOX", box: true); handover.borrowerChecked = true
        handover.setPhoto(photo); await handover.uploadPhoto(); XCTAssertTrue(handover.ready)
        let evidence = handover.evidenceID
        await handover.confirm(); XCTAssertNotNil(handover.receipt)
        parent.queue = .active; await parent.loadQueue()
        let issued = try XCTUnwrap(parent.requests.first { $0.id == pending.id })
        XCTAssertEqual(issued.items.first?.accepted_quantity, 1); XCTAssertEqual(issued.items.first?.issued_quantity, 1)
        XCTAssertEqual(issued.issue_evidence_id, evidence)
    }
    func testPartialRequestReturnKeepsOutstandingQuantityUntilFinalResolution() async throws {
        let repository = DemoStaffRepository(); let parent = state(repository)
        parent.queue = .active; await parent.loadQueue(); let initial = try XCTUnwrap(parent.requests.first)
        let handover = StaffHandoverState(parent: parent, mode: .returnRequest(initial))
        handover.returns[0].returned = 1; await handover.scan("DEMO-BOX", box: true)
        handover.remark = "One item inspected and returned."; handover.setPhoto(photo); await handover.uploadPhoto()
        XCTAssertTrue(handover.ready); await handover.confirm(); XCTAssertNotNil(handover.receipt)
        await parent.loadQueue(); let partial = try XCTUnwrap(parent.requests.first { $0.id == initial.id })
        XCTAssertEqual(partial.status, "issued"); XCTAssertEqual(partial.items[0].returned_quantity, 1)
        XCTAssertEqual(partial.return_evidence_ids.count, 1)
        XCTAssertEqual(StaffHandoverState(parent: parent, mode: .returnRequest(partial)).returns[0].remaining, 1)
        for resolution in [Components.Schemas.ReturnItemResolution(item_id: 999, returned: 1), .init(item_id: 61, returned: 2)] {
            do { _ = try await repository.returnRequest(id: initial.id, body: .init(evidence_id: 1400, box_code: "DEMO-BOX", remark: "Checked", resolutions: [resolution])); XCTFail("Invalid return changed sample records") }
            catch {}
        }
        await parent.loadQueue(); XCTAssertEqual(parent.requests.first?.items[0].returned_quantity, 1)
        let closed = try await repository.returnRequest(id: initial.id, body: .init(evidence_id: 1401, box_code: "DEMO-BOX", remark: "Remaining item missing.", resolutions: [.init(item_id: 61, missing: 1)]))
        XCTAssertEqual(closed.status, "closed"); XCTAssertEqual(closed.items[0].returned_quantity, 1)
        XCTAssertEqual(closed.items[0].missing_quantity, 1); XCTAssertEqual(closed.return_evidence_ids.count, 2)
        await parent.loadQueue(); XCTAssertFalse(parent.requests.contains { $0.id == initial.id })
    }
    func testDirectSelectedAndScannedQuantitiesPersistAcrossPartialReturns() async throws {
        let repository = DemoStaffRepository()
        let one = try await repository.createDirect(body: .init(borrower_id: 51, evidence_id: 1401, items: [.init(product_id: 901, quantity: 1)]))
        let two = try await repository.createDirect(body: .init(borrower_id: 51, evidence_id: 1402, items: [.init(product_id: 901, quantity: 2)]))
        let scanned = try await repository.createDirect(body: .init(borrower_id: 51, evidence_id: 1403, qr_payloads: ["DEMO-TOOL"]))
        XCTAssertEqual(one.items.first?.quantity, 1); XCTAssertEqual(two.items.first?.quantity, 2); XCTAssertEqual(scanned.items.first?.quantity, 1)
        XCTAssertNotEqual(one.id, two.id); XCTAssertNotEqual(one.return_items.first?.item_id, two.return_items.first?.item_id)
        XCTAssertEqual(two.issue_evidence_id, 1402)
        let itemID = try XCTUnwrap(two.return_items.first?.item_id)
        _ = try await repository.returnDirect(id: two.id, body: .init(evidence_id: 1404, notes: "One damaged item inspected.", resolutions: [.init(item_id: itemID, damaged: 1)]))
        let refreshed = try await repository.directLoans(page: 1)
        let partial = try XCTUnwrap(refreshed.results.first { $0.id == two.id })
        XCTAssertEqual(partial.status, "active"); XCTAssertEqual(partial.return_items.first?.remaining_quantity, 1)
        XCTAssertEqual(partial.return_evidence_id, 1404)
        XCTAssertEqual(refreshed.results.first { $0.id == one.id }?.return_items.first?.remaining_quantity, 1)
        for resolution in [Components.Schemas.ReturnItemResolution(item_id: 71, returned: 1), .init(item_id: itemID, returned: 2)] {
            do { _ = try await repository.returnDirect(id: two.id, body: .init(evidence_id: 1405, notes: "Checked", resolutions: [resolution])); XCTFail("Invalid direct return changed sample records") }
            catch {}
        }
        let final = try await repository.returnDirect(id: two.id, body: .init(evidence_id: 1406, notes: "Last item returned.", resolutions: [.init(item_id: itemID, returned: 1)]))
        XCTAssertEqual(final.status, "returned"); XCTAssertEqual(final.return_items.first?.remaining_quantity, 0)
        let finalList = try await repository.directLoans(page: 1)
        XCTAssertEqual(finalList.results.first { $0.id == two.id }?.status, "returned")
        XCTAssertEqual(finalList.results.first { $0.id == two.id }?.issue_evidence_id, 1402)
    }
    func testRejectionNeedsReasonAndSelectedCapability() async throws {
        let parent = state(); await parent.loadQueue(); let row = try XCTUnwrap(parent.requests.first)
        await parent.reject(row, reason: "   "); XCTAssertNotNil(parent.error); XCTAssertEqual(parent.requests.count, 1)
        let restricted = state(actions: []); await restricted.loadQueue(); await restricted.reject(row, reason: "Unavailable")
        XCTAssertNotNil(restricted.error); XCTAssertEqual(restricted.requests.count, 1)
    }
    func testIssueRequiresPhotoAndExplicitBorrowerCheck() async throws {
        let parent = state(); parent.queue = .accepted; await parent.loadQueue()
        let handover = StaffHandoverState(parent: parent, mode: .issue(try XCTUnwrap(parent.requests.first)))
        await handover.scan("DEMO-BOX", box: true); XCTAssertFalse(handover.ready)
        handover.setPhoto(photo); await handover.uploadPhoto(); XCTAssertFalse(handover.ready)
        handover.borrowerChecked = true; XCTAssertTrue(handover.ready)
        await handover.confirm(); XCTAssertNotNil(handover.receipt); XCTAssertTrue(parent.requests.isEmpty)
    }
    func testKitCountsStartEmptyAndRequireAnExplicitCountIncludingZero() async throws {
        let parent = state(kits: true); let handover = try await issue(parent)
        XCTAssertTrue(handover.kitsReady); XCTAssertTrue(handover.kitCounts.isEmpty); XCTAssertFalse(handover.ready)
        let key = try XCTUnwrap(handover.kits.first?.key); handover.kitCounts[key] = 0; XCTAssertTrue(handover.ready)
        handover.kitCounts[key] = 3; XCTAssertFalse(handover.ready)
    }
    func testRetakingPhotoClearsPreviouslyAuthorizedEvidence() async throws {
        let parent = state(); let handover = try await issue(parent)
        XCTAssertNotNil(handover.evidenceID); handover.setPhoto(photo); XCTAssertNil(handover.evidenceID); XCTAssertFalse(handover.ready)
    }
    func testFailedIssuePreservesPartialAssignmentAndRequiresFreshRequest() async throws {
        let parent = state(DemoStaffRepository(scenario: .issueConflict)); let handover = try await issue(parent)
        XCTAssertTrue(handover.ready); await handover.confirm()
        XCTAssertTrue(handover.assignmentRecorded); XCTAssertTrue(handover.needsReload); XCTAssertNil(handover.receipt)
        XCTAssertTrue(handover.notice?.contains("Box assignment was recorded") == true); XCTAssertFalse(handover.ready)
    }
    func testReturnStartsUnconfirmedAndRequiresRemark() async throws {
        let parent = state(); parent.queue = .active; await parent.loadQueue()
        let handover = StaffHandoverState(parent: parent, mode: .returnRequest(try XCTUnwrap(parent.requests.first)))
        XCTAssertEqual(handover.returns.first?.returned, 0); XCTAssertFalse(handover.itemsReady)
        handover.returns[0].returned = 2; await handover.scan("DEMO-BOX", box: true)
        handover.setPhoto(photo); await handover.uploadPhoto(); XCTAssertFalse(handover.ready)
        handover.remark = "Condition checked; both returned."; XCTAssertTrue(handover.ready)
        handover.returns[0].damaged = 1; XCTAssertFalse(handover.ready)
    }
    func testIndividualOutcomeRequiresInspectionAndProducesMatchingCounts() {
        var item = StaffReturnDraft(id: 1, label: "Sample", remaining: 2, assets: [(1, "A"), (2, "B")], returned: 0)
        XCTAssertTrue(item.outcomes.isEmpty); item.setOutcome(assetID: 1, value: "damaged")
        XCTAssertEqual(item.body.returned, 0); XCTAssertEqual(item.body.damaged, 1)
        XCTAssertEqual(item.body.assets?.first?.asset_id, 1); item.setOutcome(assetID: 1, value: "pending")
        XCTAssertEqual(item.body.damaged, 0); XCTAssertEqual(item.body.assets?.count, 0)
    }
    func testBooleanIssuedAssetMetadataCannotBecomePhysicalAssetOne() throws {
        var object = try JSONSerialization.jsonObject(with: Data(DebugStaffFixtures.request.utf8)) as! [String: Any]
        var items = object["items"] as! [[String: Any]]
        items[0]["requires_asset_qr"] = true
        items[0]["issued_assets"] = [["asset_id": true, "asset_tag": "Invalid"]]
        object["items"] = items
        let row: Components.Schemas.AdminRequest = try StaffFixture.decode(DebugStaffFixtures.request, changes: object)
        let handover = StaffHandoverState(parent: state(), mode: .returnRequest(row))
        XCTAssertFalse(handover.returns[0].metadataValid); XCTAssertFalse(handover.ready)
        XCTAssertTrue(handover.returns[0].assets.isEmpty)
        XCTAssertNil(StaffMetadata.positiveID(true)); XCTAssertNil(StaffMetadata.positiveID("1"))
        XCTAssertNil(StaffMetadata.positiveID(0)); XCTAssertEqual(StaffMetadata.positiveID(1), 1)
    }
    func testMalformedReturnCountsCannotUnderflowOrBecomeAnActionableEmptyReturn() throws {
        XCTAssertNil(StaffMetadata.remaining(issued: 0, returned: Int.max, damaged: Int.max, missing: 1))
        XCTAssertNil(StaffMetadata.remaining(issued: -1, returned: 0, damaged: 0, missing: 0))
        XCTAssertEqual(StaffMetadata.remaining(issued: Int.max, returned: Int.max, damaged: 0, missing: 0), 0)
        var object = try JSONSerialization.jsonObject(with: Data(DebugStaffFixtures.request.utf8)) as! [String: Any]
        var items = object["items"] as! [[String: Any]]
        items[0]["issued_quantity"] = 0; items[0]["returned_quantity"] = Int.max; items[0]["damaged_quantity"] = Int.max
        object["items"] = items
        let row: Components.Schemas.AdminRequest = try StaffFixture.decode(DebugStaffFixtures.request, changes: object)
        let handover = StaffHandoverState(parent: state(), mode: .returnRequest(row))
        XCTAssertFalse(handover.returns[0].metadataValid); XCTAssertFalse(handover.ready)
    }
    func testLateCameraCallbackCannotRepopulateInvalidatedHandover() {
        let handover = StaffHandoverState(parent: state(), mode: .directIssue)
        handover.setPhoto(photo); XCTAssertNotNil(handover.photo)
        handover.invalidate(); handover.setPhoto(photo)
        XCTAssertNil(handover.photo); XCTAssertNil(handover.evidenceID); XCTAssertFalse(handover.ready)
    }
    func testLateCameraCallbackDuringUploadPreservesOriginalPhotoAndSettlesBusy() async throws {
        let gate = StaffReadGate()
        let parent = state(DemoStaffRepository(beforeEvidence: { await gate.suspend() }))
        parent.queue = .accepted; await parent.loadQueue()
        let handover = StaffHandoverState(parent: parent, mode: .issue(try XCTUnwrap(parent.requests.first)))
        let original = photo
        let replacement = Data([0xff, 0xd8, 0xff, 0xe0, 8, 7, 6, 5])
        handover.setPhoto(original)
        let pending = Task { await handover.uploadPhoto() }
        await gate.waitUntilStarted()

        XCTAssertTrue(handover.busy)
        XCTAssertNil(handover.evidenceID)
        handover.setPhoto(replacement)
        XCTAssertEqual(handover.photo, original)
        XCTAssertTrue(handover.busy)

        await gate.release(); await pending.value
        XCTAssertFalse(handover.busy)
        XCTAssertEqual(handover.photo, original)
        XCTAssertEqual(handover.evidenceID, 1301)
        XCTAssertNil(handover.error)

        // A later deliberate retake is allowed and invalidates the old evidence association.
        handover.setPhoto(replacement)
        XCTAssertEqual(handover.photo, replacement)
        XCTAssertNil(handover.evidenceID)
    }
    func testDirectHandoutUsesUserIDAndRejectsMembershipIDAsBorrower() async throws {
        let parent = state(); let handover = StaffHandoverState(parent: parent, mode: .directIssue)
        await handover.loadBorrowers(); await handover.loadProducts(); handover.bulkQuantities[901] = 1
        handover.setPhoto(photo); await handover.uploadPhoto(); handover.borrowerID = 81
        XCTAssertFalse(handover.ready); handover.borrowerID = 51; XCTAssertTrue(handover.ready)
    }
    func testChangingReturnCountsInvalidatesKitPreview() async throws {
        let parent = state(kits: true); parent.queue = .active; await parent.loadQueue()
        let handover = StaffHandoverState(parent: parent, mode: .returnRequest(try XCTUnwrap(parent.requests.first)))
        handover.returns[0].returned = 1; await handover.prepareKits(); XCTAssertTrue(handover.kitsReady)
        handover.returns[0].returned = 2; XCTAssertFalse(handover.kitsReady); XCTAssertTrue(handover.kitCounts.isEmpty)
    }
    func testCheckInResolveRequiresSeparateConfirmation() async throws {
        let parent = state(); await parent.loadEvents(); let event = try XCTUnwrap(parent.events.first)
        let checkin = StaffCheckInState(parent: parent, event: event); await checkin.resolve("DEMO-EVENT")
        XCTAssertTrue(checkin.canConfirm); XCTAssertEqual(checkin.person?.status, "registered"); XCTAssertNil(checkin.confirmation)
        await checkin.resolve("DEMO-EVENT"); XCTAssertEqual(checkin.person?.status, "registered")
        await checkin.confirm(); XCTAssertNotNil(checkin.confirmation); XCTAssertNil(checkin.person)
        await checkin.resolve("DEMO-EVENT"); XCTAssertEqual(checkin.person?.status, "attended"); XCTAssertFalse(checkin.canConfirm)
    }
    func testWaitlistedRegistrationCannotBeConfirmed() async throws {
        let parent = state(DemoStaffRepository(scenario: .waitlisted)); await parent.loadEvents()
        let checkin = StaffCheckInState(parent: parent, event: try XCTUnwrap(parent.events.first)); await checkin.resolve("DEMO-EVENT")
        XCTAssertEqual(checkin.person?.status, "waitlisted"); XCTAssertFalse(checkin.canConfirm)
        await checkin.confirm(); XCTAssertNil(checkin.confirmation)
    }
    func testCheckInConflictClearsPersonAndRequiresRescanWithoutClaimingAttendance() async throws {
        let parent = state(DemoStaffRepository(scenario: .attendanceConflict)); await parent.loadEvents()
        let checkin = StaffCheckInState(parent: parent, event: try XCTUnwrap(parent.events.first)); await checkin.resolve("DEMO-EVENT"); await checkin.confirm()
        XCTAssertNil(checkin.person); XCTAssertNil(checkin.confirmation); XCTAssertFalse(checkin.canConfirm)
        XCTAssertEqual(checkin.error, "This registration changed. Scan the code again to check its latest status.")
    }
    func testScopeInvalidationClearsPhotoScansPersonAndRows() async throws {
        let parent = state(); let handover = try await issue(parent); await parent.loadEvents()
        let checkin = StaffCheckInState(parent: parent, event: try XCTUnwrap(parent.events.first)); await checkin.resolve("DEMO-EVENT")
        parent.invalidate(); XCTAssertNil(handover.photo); XCTAssertNil(handover.evidenceID); XCTAssertTrue(handover.scans.isEmpty)
        XCTAssertNil(checkin.person); XCTAssertTrue(parent.requests.isEmpty); XCTAssertTrue(parent.events.isEmpty)
        await handover.confirm(); XCTAssertNil(handover.receipt); await checkin.confirm(); XCTAssertNil(checkin.confirmation)
    }
    func testBookingDecisionUsesReturnedServerState() async throws {
        let parent = state(); await parent.loadBookings(spaceID: 901); let row = try XCTUnwrap(parent.bookings.first)
        await parent.decideBooking(row, approve: true); XCTAssertEqual(parent.bookings.first?.status.value1.rawValue, "confirmed")
    }
    func testBookingConflictReconcilesAuthoritativeStateBeforeAnotherDecision() async throws {
        let parent = state(DemoStaffRepository(scenario: .bookingConflict)); await parent.loadBookings(spaceID: 901)
        await parent.decideBooking(try XCTUnwrap(parent.bookings.first), approve: true)
        XCTAssertNotNil(parent.error); XCTAssertEqual(parent.bookings.first?.status.value1.rawValue, "confirmed"); XCTAssertFalse(parent.busy)
    }
    func testAuthorityRefusalPreventsAnotherInFlightResourceFromPublishingPrivateRows() async {
        let gate = StaffReadGate()
        let parent = state(DemoStaffRepository(beforeEvents: { await gate.suspend() }))
        let pending = Task { await parent.loadEvents() }
        await gate.waitUntilStarted()
        parent.refuse(APIError(status: 403, code: "forbidden", detail: "Your staff access changed."))
        await gate.release(); await pending.value
        XCTAssertFalse(parent.isActive); XCTAssertTrue(parent.events.isEmpty); XCTAssertFalse(parent.can("manage_events"))
    }
    func testActualNextPageAndDuplicatePageRefusal() throws {
        XCTAssertEqual(try StaffPaging.next("?page=3", after: 1), 3)
        for raw in ["?page=1", "?page=2&page=3", "?page=-2", "?page=x"] { XCTAssertThrowsError(try StaffPaging.next(raw, after: 1)) }
    }
}

private actor StaffReadGate {
    private var started = false
    private var ready: CheckedContinuation<Void, Never>?
    private var resumed: CheckedContinuation<Void, Never>?
    func suspend() async {
        started = true; ready?.resume(); ready = nil
        await withCheckedContinuation { resumed = $0 }
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { ready = $0 } } }
    func release() { resumed?.resume(); resumed = nil }
}
#endif

final class StaffOperationTests: XCTestCase {
    func testRetainedStaffRepositoryCannotFirstReadOrIssueUnderReplacementAccount() async throws {
        let fixture = try await OwnedRepositoryFixture.make(); let probe = fixture.probe
        let repository = LiveStaffRepository(service: fixture.service, expectedCredentials: fixture.credentials,
            makerspaceID: 7, origin: fixture.origin, onUnauthorized: { _ in probe.notified() }, onForbidden: { probe.notified() })
        try await fixture.replaceAccount()
        let operations: [@Sendable () async throws -> Void] = [
            { _ = try await repository.requests(queue: .pending, page: 1) },
            { _ = try await repository.assignBox(id: 601, body: .init(box_code: "retired-code")) },
            { _ = try await repository.approveBooking(id: 1001) }
        ]
        for operation in operations {
            do { try await operation(); XCTFail("Retired staff authority sent a request") }
            catch { XCTAssertTrue(APIError.isCancellation(error)) }
        }
        XCTAssertEqual(probe.counts.requests, 0); XCTAssertEqual(probe.counts.callbacks, 0)
    }
    override func tearDown() { StubProtocol.lock.lock(); StubProtocol.handler = nil; StubProtocol.lock.unlock() }
    private func repository(handler: @escaping (URLRequest) throws -> (Int, String)) async throws -> LiveStaffRepository {
        StubProtocol.lock.lock(); StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "spaceworks.example")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer staff-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
            for key in ["Cookie", "Origin", "Referer"] { XCTAssertNil(request.value(forHTTPHeaderField: key)) }
            let (status, json) = try handler(request); return (status, ["Content-Type": "application/json"], Data(json.utf8))
        }; StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        let origin = try ServerOrigin("https://spaceworks.example")
        let service = SpaceWorksService(origin: origin, session: DeviceSession.make(configuration: config), initialTokens: .init(access: "staff-access", refresh: "staff-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7, 9])
        return LiveStaffRepository(service: service, expectedCredentials: await service.refresh.snapshot(), makerspaceID: 7, origin: origin)
    }
    func testAll24GeneratedStaffOperationsRetainScopeExactRoutesAndTypedBodies() async throws {
        var calls = Set<String>()
        let repo = try await repository { request in
            let path = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let key = "\(request.httpMethod!) \(path)"; calls.insert(key)
            if path.contains("pending-requests") || path.contains("accepted-requests") || path.contains("active-loans") { return (200, try StaffFixture.page(DebugStaffFixtures.request)) }
            if path.contains("admin/requests/") { return (200, DebugStaffFixtures.request) }
            if path.hasSuffix("qr/resolve") { return (200, DebugStaffFixtures.qr) }
            if path.hasSuffix("direct-loan-members") { return (200, DebugStaffFixtures.members) }
            if path.hasSuffix("inventory") { return (200, DebugStaffFixtures.inventory) }
            if path.hasSuffix("containers") { return (200, DebugStaffFixtures.containers) }
            if path.hasSuffix("direct-loans") { return request.httpMethod == "POST" ? (201, DebugStaffFixtures.loan) : (200, try StaffFixture.page(DebugStaffFixtures.loan)) }
            if path.contains("direct-loans/") { return (200, DebugStaffFixtures.loan) }
            if path.hasSuffix("evidence-url") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["evidence_type"] as? String, "issue"); XCTAssertEqual(body["size_bytes"] as? Int, 3)
                return (201, #"{"evidence_id":1301,"upload_url":"https://storage.example.invalid/upload","object_key":"sample","fields":{"key":"sample"}}"#)
            }
            if path.hasSuffix("kit-checklist-preview") { return (200, DebugStaffFixtures.kits) }
            if path.hasSuffix("check-in/resolve") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["checkin_token"] as? String, "opaque-checkin"); XCTAssertNil(body["payload"])
                return (200, DebugStaffFixtures.checkin)
            }
            if path.hasSuffix("mark-attended") {
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]; XCTAssertEqual(body["source"] as? String, "qr")
                return (200, DebugStaffFixtures.registration)
            }
            if path.hasSuffix("events") { return (200, try StaffFixture.page(DebugStaffFixtures.event, extra: ["default_registration_audience": "members"])) }
            if path.hasSuffix("spaces") { return (200, try StaffFixture.page(DebugStaffFixtures.space)) }
            if path.hasSuffix("bookings") { return (200, try StaffFixture.page(DebugStaffFixtures.booking)) }
            if path.hasSuffix("approve") || path.hasSuffix("reject") { XCTAssertTrue(requestBody(request).isEmpty); return (200, DebugStaffFixtures.booking) }
            XCTFail("Unexpected generated staff route: \(key)"); return (500, "{}")
        }
        for queue in StaffQueue.allCases { _ = try await repo.requests(queue: queue, page: 1) }
        _ = try await repo.accept(id: 601, body: .init(accepted_quantities: [.init(item_id: 61, quantity: 2)]))
        _ = try await repo.reject(id: 601, body: .init(reason: "Equipment unavailable"))
        _ = try await repo.assignBox(id: 601, body: .init(box_code: "opaque-box"))
        _ = try await repo.issue(id: 601, body: .init(evidence_id: 1301))
        _ = try await repo.returnRequest(id: 601, body: .init(evidence_id: 1301, box_code: "opaque-box", remark: "Checked", resolutions: [.init(item_id: 61, returned: 1)]))
        _ = try await repo.resolveQR(body: .init(payload: "opaque-code"))
        _ = try await repo.directLoans(page: 1); _ = try await repo.directMembers(page: 1); _ = try await repo.inventory(page: 1, search: "tool"); _ = try await repo.containers(page: 1)
        _ = try await repo.createDirect(body: .init(borrower_id: 51, evidence_id: 1301, items: [.init(product_id: 901, quantity: 1)]))
        _ = try await repo.returnDirect(id: 701, body: .init(evidence_id: 1301, notes: "Checked"))
        _ = try await repo.evidence(body: .init(evidence_type: .issue, content_type: "image/jpeg", size_bytes: 3))
        _ = try await repo.kitPreview(body: .init(request_id: 601)); _ = try await repo.events(page: 1)
        _ = try await repo.resolveCheckIn(eventID: 801, body: .init(checkin_token: "opaque-checkin"))
        _ = try await repo.markAttended(registrationID: 1101, body: .init(source: .init(value1: .qr)))
        _ = try await repo.spaces(page: 1); _ = try await repo.bookings(spaceID: 901, page: 1)
        _ = try await repo.approveBooking(id: 1001); _ = try await repo.rejectBooking(id: 1001)
        XCTAssertEqual(calls.count, 24)
    }
    func testRetainedStaffRepositoryRefusesScopeDriftBeforeSendingAnIDOnlyMutation() async throws {
        var calls = 0
        let repo = try await repository { _ in calls += 1; return (200, DebugStaffFixtures.booking) }
        try await repo.service.makerspace.select(9, activeMemberships: [7, 9])
        do { _ = try await repo.approveBooking(id: 1001); XCTFail("Old scope sent a mutation") } catch { XCTAssertEqual(calls, 0) }
    }
    func testNextPageCannotChangeOriginResourceOrRegress() async throws {
        let repo = try await repository { _ in (200, #"{"count":1,"next":"https://evil.example/?page=2","previous":null,"results":[]}"#) }
        do { _ = try await repo.requests(queue: .pending, page: 1); XCTFail("Foreign page accepted") } catch { XCTAssertNotNil(error) }
    }
}
