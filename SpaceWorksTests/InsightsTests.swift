import XCTest
import Foundation
import SpaceWorksAPI
@testable import SpaceWorks

private actor InsightsFake: InsightsRepository {
    var messagingJSON = DebugAuthFixtures.messaging
    var consentFailure: APIError?
    var consentCalls: [(String, Bool)] = []
    func configure(messaging: String) { messagingJSON = messaging }
    func configure(consentFailure: APIError?) { self.consentFailure = consentFailure }
    private func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
    func usage() async throws -> Components.Schemas.MemberUsage { try decode(DebugAuthFixtures.usage) }
    func dashboard() async throws -> Components.Schemas.Dashboard { try decode(DebugAuthFixtures.dashboard) }
    func messaging() async throws -> Components.Schemas.MemberMessaging { try decode(messagingJSON) }
    func consent(channel: Components.Schemas.Channel06eEnum, optIn: Bool) async throws -> Components.Schemas.MemberMessaging {
        consentCalls.append((channel.rawValue, optIn))
        if let consentFailure { throw consentFailure }
        return try decode(messagingJSON.replacingOccurrences(of: #""consented":false"#, with: #""consented":\#(optIn)"#))
    }
}

@MainActor final class InsightsTests: XCTestCase {
    func testUsageSeriesUsesTheDeclaredFieldsAndKeepsServerNumbersAsText() throws {
        let usage = try JSONDecoder().decode(Components.Schemas.MemberUsage.self, from: Data(DebugAuthFixtures.usage.utf8))
        let series = UsageSeries.from(try XCTUnwrap(usage.loans).monthly)
        XCTAssertEqual(series.points, [UsagePoint(label: "2026-09", value: "2", amount: 2), UsagePoint(label: "2026-10", value: "1", amount: 1)])
        XCTAssertEqual(series.unit, "loans"); XCTAssertEqual(series.summary, "Loans by month")
        XCTAssertNil(usage.machines, "Absent sections stay absent, never zero")
        XCTAssertTrue(UsageSeries.from(try XCTUnwrap(usage.payments).totals).points.isEmpty)
    }

    func testDashboardShowsOnlyReportedNonZeroCountersAndHidesAnalyticsForHandover() throws {
        let glance = StaffGlance.from(try JSONDecoder().decode(Components.Schemas.Dashboard.self, from: Data(DebugAuthFixtures.dashboard.utf8)))
        XCTAssertEqual(glance.counters, [StaffCounter(key: "pending_requests", value: 2)], "Zero and omitted counters are not tiles")
        XCTAssertEqual(glance.queue.map(\.key), ["ready_to_issue", "due_returns", "pickups"])
        XCTAssertEqual(glance.outstanding.first?.currency, "INR")
        let handover = #"{"scope_mode":"handover","widgets":[{"key":"loans","title":"Loans","required_action":"view_reports","required_modules":[],"kind":"count","report_keys":[],"default_period":7,"data":{"count":4},"chart_spec":null}]}"#
        XCTAssertTrue(StaffGlance.from(try JSONDecoder().decode(Components.Schemas.Dashboard.self, from: Data(handover.utf8))).widgets.isEmpty)
        let full = handover.replacingOccurrences(of: #""handover""#, with: #""full""#)
        XCTAssertEqual(StaffGlance.from(try JSONDecoder().decode(Components.Schemas.Dashboard.self, from: Data(full.utf8))).widgets,
                       [StaffWidget(key: "loans", title: "Loans", headline: "4")])
        XCTAssertEqual(StaffGlance.label("due_returns"), "Due back")
    }

    func testOptInNeedsAVerifiedAvailableUnsuppressedChannel() async {
        let fake = InsightsFake()
        let state = InsightsState(repository: fake)
        await state.refreshMessaging()
        await state.setConsent(.sms, optIn: true)
        let refused = await fake.consentCalls
        XCTAssertTrue(refused.isEmpty, "An unverified phone cannot opt in")
        await fake.configure(messaging: DebugAuthFixtures.messaging.replacingOccurrences(of: #""phone_verified":false,"phone_masked":"""#, with: #""phone_verified":true,"phone_masked":"+91 •••• 3210""#))
        await state.refreshMessaging()
        await state.setConsent(.sms, optIn: true)
        guard case .ready(let value) = state.messaging else { return XCTFail("Consent result must come from the server") }
        XCTAssertTrue(value.sms.consented)
    }

    func testRefusedConsentShowsTheServerDetailAndRefetches() async {
        let fake = InsightsFake()
        await fake.configure(messaging: DebugAuthFixtures.messaging.replacingOccurrences(of: #""consented":false,"phone_verified":false"#, with: #""consented":true,"phone_verified":true"#))
        await fake.configure(consentFailure: APIError(status: 409, code: "consent_conflict", detail: "This number changed. Verify it again."))
        let state = InsightsState(repository: fake)
        await state.refreshMessaging()
        await state.setConsent(.sms, optIn: false)
        XCTAssertEqual(state.consentError, "This number changed. Verify it again.")
        guard case .ready(let value) = state.messaging else { return XCTFail("The authoritative state is refetched") }
        XCTAssertTrue(value.sms.consented)
    }

    func testPhoneRestoreNeedsMatchingPasswordsAndNeverStartsASession() async {
        var restored: (String, String, String, String)?
        let form = AccountRestoreState(begin: { _ in .init(challenge: "bound", expires: Date().addingTimeInterval(180)) }, restore: { phone, code, password, challenge in
            restored = (phone, code, password, challenge)
            return try JSONDecoder().decode(Components.Schemas.AccountRestoreResult.self, from: Data(#"{"restored":true,"detail":"Restored."}"#.utf8))
        })
        form.number = "+91 98765 43210"; await form.send()
        XCTAssertEqual(form.step, .code)
        form.code = "123456"; form.password = "New-password-1"; form.confirmation = "different"; await form.submit()
        XCTAssertEqual(form.error, "Enter matching new passwords."); XCTAssertNil(restored)
        form.confirmation = "New-password-1"; await form.submit()
        XCTAssertEqual(form.step, .restored); XCTAssertEqual(form.password, "", "Secrets are cleared")
        XCTAssertEqual(restored?.0, "+919876543210"); XCTAssertEqual(restored?.3, "bound")
    }

    func testGeneratedInsightOperationsUseTheSelectedMakerspace() async throws {
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
            let json = ["Content-Type": "application/json"]
            switch request.url!.path {
            case "/api/v1/member/makerspaces/7/my-usage": return (200, json, Data(DebugAuthFixtures.usage.utf8))
            case "/api/v1/admin/makerspace/7/dashboard": return (200, json, Data(DebugAuthFixtures.dashboard.utf8))
            case "/api/v1/me/messaging":
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "7")
                return (200, json, Data(DebugAuthFixtures.messaging.utf8))
            case "/api/v1/me/messaging/consent":
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
                XCTAssertEqual(body?["makerspace"] as? Int, 7); XCTAssertEqual(body?["channel"] as? String, "sms"); XCTAssertEqual(body?["action"] as? String, "opted_out")
                return (200, json, Data(DebugAuthFixtures.messaging.utf8))
            default: XCTFail("Unexpected request \(request.url!)"); return (500, json, Data("{}".utf8))
            }
        }
        StubProtocol.lock.unlock()
        let configuration = DeviceSession.configuration(); configuration.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: try ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: configuration),
                                       initialTokens: TokenPair(access: "fixture-access", refresh: "fixture-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7])
        let repository = LiveInsightsRepository(service: service, expectedCredentials: await service.refresh.snapshot(), makerspaceID: 7)
        let usage = try await repository.usage(); XCTAssertTrue(usage.usage_available)
        let dashboard = try await repository.dashboard(); XCTAssertEqual(dashboard.scope_mode, .full)
        _ = try await repository.messaging()
        _ = try await repository.consent(channel: .sms, optIn: false)
    }
}
