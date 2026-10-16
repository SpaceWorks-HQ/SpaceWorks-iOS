import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class MemberActionsTests: XCTestCase {
    func testCartRetryRetainsIdempotencyWhileEditingCreatesNewAttempt() async throws {
        let repository = DemoMemberActionsRepository(scenario: .refused)
        let state = RequestCartState(repository: repository)
        state.add(try await DemoMemberRepository().product(1))
        let first = state.attemptKey
        await state.submit(); XCTAssertEqual(state.attemptKey, first); XCTAssertNil(state.receipt); XCTAssertEqual(state.lines.count, 1)
        state.purpose = "Make a circuit"; XCTAssertNotEqual(state.attemptKey, first)
        let second = state.attemptKey; await state.submit(); XCTAssertEqual(state.attemptKey, second)
        await repository.preview(.success); await state.submit()
        XCTAssertEqual(state.receipt?.status, "pending"); XCTAssertTrue(state.lines.isEmpty); XCTAssertNotEqual(state.attemptKey, second)
    }
    func testDuplicateDemoRequestKeyReturnsSameReceiptAndOnlyOneHistoryRow() async throws {
        let store = DemoMemberStore(); let repository = DemoMemberActionsRepository(store: store)
        let input = [Components.Schemas.RequestItemInput(product_id: 1, quantity: 2)]
        let initial = try JSONSerialization.jsonObject(with: Data(await store.activity().utf8)) as! [String: Any]
        let before = (initial["request_history"] as! [[String: Any]]).count
        let first = try await repository.submit(items: input, purpose: "A project", key: "stable-attempt")
        let second = try await repository.submit(items: input, purpose: "A project", key: "stable-attempt")
        XCTAssertEqual(first.public_token, second.public_token)
        let final = try JSONSerialization.jsonObject(with: Data(await store.activity().utf8)) as! [String: Any]
        XCTAssertEqual((final["request_history"] as! [[String: Any]]).count, before + 1)
        do { _ = try await repository.submit(items: input, purpose: "Changed project", key: "stable-attempt"); XCTFail("Reused key accepted different content") }
        catch { XCTAssertEqual(APIError.status(error), 409) }
    }
    func testProfileFailurePreservesUnsavedEditsAndExplicitDiscardRestoresConfirmedData() async {
        let repository = DemoMemberActionsRepository(); let state = ProfileEditorState(repository: repository)
        await state.load(); XCTAssertTrue(state.loaded)
        state.displayName = "Meera Maker"; XCTAssertTrue(state.dirty)
        await repository.preview(.refused); await state.save()
        XCTAssertEqual(state.displayName, "Meera Maker"); XCTAssertTrue(state.dirty); XCTAssertNotNil(state.error)
        state.discard(); XCTAssertEqual(state.displayName, "Meera Nair"); XCTAssertFalse(state.dirty)
        await repository.preview(.success); state.displayName = "Meera Maker"; await state.save()
        XCTAssertEqual(state.notice, "Profile saved."); XCTAssertFalse(state.dirty)
    }
    func testMandatoryMessagesDoNotLockOptionalPreferencesAndUnavailableCannotEnable() async throws {
        let repository = DemoMemberActionsRepository(); let state = CommunicationPreferencesState(repository: repository)
        await state.load()
        let safety = try XCTUnwrap(state.cells.first { !$0.mandatory_events.isEmpty })
        await state.set(safety, enabled: false)
        XCTAssertEqual(state.cells.first { $0.feature == safety.feature && $0.channel == safety.channel }?.enabled, false)
        XCTAssertEqual(state.cells.first { $0.feature == safety.feature && $0.channel == safety.channel }?.mandatory_events, safety.mandatory_events)
        let unavailable = try XCTUnwrap(state.cells.first { !$0.available })
        await state.set(unavailable, enabled: true)
        XCTAssertNotNil(state.error); XCTAssertEqual(state.cells.first { !$0.available }?.enabled, false)
    }
    func testPreferenceWriteRefusalKeepsLastConfirmedValue() async throws {
        let repository = DemoMemberActionsRepository(); let state = CommunicationPreferencesState(repository: repository)
        await state.load(); let cell = try XCTUnwrap(state.cells.first)
        await repository.preview(.refused); await state.set(cell, enabled: !cell.enabled)
        XCTAssertEqual(state.cells.first?.enabled, cell.enabled); XCTAssertNotNil(state.error)
    }
    func testBookingEditsInvalidateAvailabilityAndConflictNeverBecomesConfirmed() async throws {
        let repository = DemoMemberActionsRepository()
        let spaces = try await DemoMemberRepository().spaces()
        let space = try XCTUnwrap(spaces.first)
        let state = BookingState(repository: repository, space: space)
        await state.check(); XCTAssertNotNil(state.availability)
        state.end = state.end.addingTimeInterval(60); XCTAssertNil(state.availability)
        await state.confirm(); XCTAssertNil(state.result)
        await state.check(); await repository.preview(.conflict); await state.confirm()
        XCTAssertNil(state.result); XCTAssertNil(state.availability); XCTAssertNotNil(state.error)
        await repository.preview(.success); await state.check(); await state.confirm(); XCTAssertEqual(state.result?.status.value1, .confirmed)
    }
    func testUnknownCustomQuestionAndMalformedNumbersFailClosed() throws {
        let form = MemberCustomForm(data: Data(#"[{"id":"q1","label":"How many?","type":"number","required":true,"options":[]}]"#.utf8))
        form.text["q1"] = "12oops"; XCTAssertNil(form.validatedAnswers()); XCTAssertNotNil(form.errors["q1"])
        form.text["q1"] = "12"; XCTAssertNotNil(form.validatedAnswers())
        let unknown = MemberCustomForm(data: Data(#"[{"id":"q1","label":"Unknown field","type":"future_secret","required":true,"options":[]}]"#.utf8))
        XCTAssertTrue(unknown.unavailable); XCTAssertNil(unknown.validatedAnswers())
        XCTAssertTrue(MemberCustomForm(data: Data("not-json".utf8)).unavailable)
    }
    func testEventResultsRemainServerSelectedAndTicketUsesActualActivityRegistrationID() async throws {
        let store = DemoMemberStore(); let repository = DemoMemberActionsRepository(store: store)
        let rows = try await DemoMemberRepository().events(); let event = try XCTUnwrap(rows.first)
        for scenario in [DemoMemberActionsRepository.Scenario.pending, .waitlisted, .success] {
            await repository.preview(scenario)
            let state = EventRegistrationState(repository: repository, event: event)
            await state.submit()
            XCTAssertEqual(state.result?.status.value1.rawValue, scenario == .pending ? "pending_approval" : scenario == .waitlisted ? "waitlisted" : "registered")
            let reader = DemoMemberRepository(store: store); let activity = try await reader.activity()
            let registration = try XCTUnwrap(activity.event_registrations?.first { $0.registration_id == 777 })
            XCTAssertEqual(registration.status, state.result?.status.value1.rawValue)
            if scenario == .success {
                let qr = try await repository.eventQR(registration: registration.registration_id); XCTAssertNotNil(NativeQRSVG.image(qr))
            } else {
                do { _ = try await repository.eventQR(registration: registration.registration_id); XCTFail("Unconfirmed ticket returned a QR") }
                catch { XCTAssertEqual(APIError.status(error), 403) }
            }
        }
        _ = try await repository.cancelEvent(registration: 777)
        do { _ = try await repository.eventQR(registration: 777); XCTFail("Cancelled ticket returned a QR") }
        catch { XCTAssertEqual(APIError.status(error), 403) }
    }
    func testDemoMutationRefetchUpdatesActivityAndNativeDraftInvalidationPreventsNewWrites() async throws {
        let store = DemoMemberStore(); let repository = DemoMemberActionsRepository(store: store)
        let reader = DemoMemberRepository(store: store)
        let before = try await reader.activity().request_history?.count ?? 0
        let cart = RequestCartState(repository: repository); cart.add(try await reader.product(1)); await cart.submit()
        let after = try await reader.activity().request_history?.count ?? 0
        XCTAssertEqual(after, before + 1)
        cart.invalidate(); cart.add(try await reader.product(1)); await cart.submit()
        XCTAssertNil(cart.receipt); XCTAssertTrue(cart.lines.isEmpty)
    }

    func testBootstrapGatesProfileAndPreferencesAndWrongMakerspaceFailsClosed() async throws {
        let valid = MemberCapabilities(repository: DemoMemberActionsRepository(), makerspaceID: 7)
        XCTAssertFalse(valid.selfService); XCTAssertFalse(valid.preferences)
        await valid.load(); XCTAssertTrue(valid.selfService); XCTAssertTrue(valid.preferences); XCTAssertTrue(valid.digests)
        let wrong = MemberCapabilities(repository: DemoMemberActionsRepository(), makerspaceID: 99)
        await wrong.load(); XCTAssertNil(wrong.bootstrap); XCTAssertFalse(wrong.selfService); XCTAssertNotNil(wrong.error)
        var object = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.bootstrap.utf8)) as! [String: Any]
        object["modules"] = []; object["features"] = []
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let disabled = MemberCapabilities(repository: DemoMemberActionsRepository(bootstrapJSON: json), makerspaceID: 7)
        await disabled.load(); XCTAssertFalse(disabled.selfService); XCTAssertFalse(disabled.preferences)
        valid.invalidate(); XCTAssertNil(valid.bootstrap)
    }
    func testDisabledDigestFeatureDoesNotPreventOptionalChannelUpdates() async throws {
        let state = CommunicationPreferencesState(repository: DemoMemberActionsRepository())
        await state.load(); let email = try XCTUnwrap(state.cells.first { $0.channel.rawValue == "email" })
        state.digestsAllowed = false
        await state.digest(email, enabled: true)
        XCTAssertEqual(state.cells.first?.daily_digest, false)
        await state.set(email, enabled: false)
        XCTAssertEqual(state.cells.first?.enabled, false); XCTAssertEqual(state.cells.first?.daily_digest, false)
    }

    func testTicketThrottleClearsPreviousQRCodeAndCancellationNeverLeavesItVisible() async throws {
        let store = DemoMemberStore(); let repository = DemoMemberActionsRepository(store: store)
        _ = try await repository.register(event: "sample", input: .init())
        let activity = try await DemoMemberRepository(store: store).activity()
        let registration = try XCTUnwrap(activity.event_registrations?.first)
        let state = MemberTicketState(registration: registration, repository: repository)
        await state.load(); XCTAssertNotNil(state.image)
        await repository.preview(.throttled); await state.load(); XCTAssertNil(state.image)
        let deadline = try XCTUnwrap(state.retryAfter)
        await repository.preview(.success); await state.load(); XCTAssertNil(state.image)
        await state.load(now: deadline.addingTimeInterval(1)); XCTAssertNotNil(state.image)
        await state.cancel(now: deadline.addingTimeInterval(1)); XCTAssertTrue(state.cancelled); XCTAssertNil(state.image)
        await state.load(now: deadline.addingTimeInterval(1)); XCTAssertNil(state.image)
        state.invalidate(); XCTAssertNil(state.image)
    }

}
