import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

final class MemberActionsNetworkingTests: XCTestCase {
    func testGeneratedMemberWritesUseOnlyContractFieldsAndAuthoritativeStatusResults() async throws {
        let token = "a8a33ab0-c138-4c0a-85eb-fdcb6b75318f"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calls = 0
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer native-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.value(forHTTPHeaderField: "X-Publishable-Key"))
            let path = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var status = 200; var type = "application/json"; let json: String
            if path == "api/v1/bootstrap" {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "slug" })?.value, "fab-lab-kochi")
                json = DebugMemberFixtures.bootstrap
            } else if path.hasSuffix("/requests") {
                XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "reviewed-attempt")
                let body = try Self.body(request)
                XCTAssertEqual(Set(body.keys), Set(["requested_for", "items"]))
                let item = (body["items"] as! [[String: Any]])[0]
                XCTAssertEqual(Set(item.keys), Set(["product_id", "quantity"])); XCTAssertEqual(item["quantity"] as? Int, 2)
                status = 201; json = "{\"public_token\":\"\(token)\",\"status\":\"pending\"}"
            } else if path.hasSuffix("/renew") {
                XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.httpBody); XCTAssertNil(request.httpBodyStream)
                json = #"{"id":4,"return_due_at":"2027-01-25T08:00:00Z","renewal_count":2}"#
            } else if path.hasSuffix("/availability") {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertNotNil(query.first { $0.name == "starts_at" }); XCTAssertNotNil(query.first { $0.name == "ends_at" })
                json = "{\"public_token\":\"\(token)\",\"starts_at\":\"2027-01-15T08:00:00Z\",\"ends_at\":\"2027-01-15T09:00:00Z\",\"timezone\":\"Asia/Kolkata\",\"opening_intervals\":[],\"availability\":null}"
            } else if path.hasSuffix("/book") {
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try Self.body(request); XCTAssertNotNil(body["starts_at"]); XCTAssertNotNil(body["ends_at"]); XCTAssertNil(body["status"])
                status = 201; json = #"{"status":"pending"}"#
            } else if path.hasSuffix("/register") {
                XCTAssertEqual(request.httpMethod, "POST"); let body = try Self.body(request)
                XCTAssertEqual(body["ticket_type_id"] as? Int, 1); XCTAssertNil(body["registration_id"])
                status = 201; json = #"{"status":"waitlisted"}"#
            } else if path.contains("/my-bookings/") && path.hasSuffix("/cancel") {
                XCTAssertEqual(request.httpMethod, "POST")
                let fixture = try JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.bookings.utf8)) as! [String: Any]
                var row = (fixture["results"] as! [[String: Any]])[0]; row["status"] = "cancelled"; row["can_cancel"] = false; row["public_token"] = token
                json = String(decoding: try JSONSerialization.data(withJSONObject: row), as: UTF8.self)
            } else if path.hasSuffix("/cancel") {
                XCTAssertEqual(request.httpMethod, "POST"); json = #"{"status":"cancelled"}"#
            } else if path.hasSuffix("/qr") {
                type = "image/svg+xml"; json = #"<svg viewBox="0 0 8 8"><path d="M2 2h2v2H2z"/></svg>"#
            } else if path.hasSuffix("/profile") {
                if request.httpMethod == "PATCH" { let body = try Self.body(request); XCTAssertEqual(Set(body.keys), Set(["display_name"])) }
                json = #"{"display_name":"Meera Maker","first_name":"Meera","last_name":"Nair","phone":""}"#
            } else if path.contains("/preferences/") {
                if request.httpMethod == "PATCH" { let body = try Self.body(request); XCTAssertEqual(body["enabled"] as? Bool, false); XCTAssertNil(body["mandatory_events"]) }
                json = #"{"cells":[]}"#
            } else { XCTFail("Unexpected generated action route: \(path)"); json = "{}" }
            return (status, ["Content-Type": type], Data(json.utf8))
        }
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        let service = SpaceWorksService(origin: try ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: config), initialTokens: TokenPair(access: "native-access", refresh: "native-refresh"))
        try await service.makerspace.select(7, activeMemberships: [7])
        try await service.withMakerspace(7) {
            let bootstrap = try await service.memberBootstrap(slug: "fab-lab-kochi"); XCTAssertEqual(bootstrap.makerspace.id, 7)
            let receipt = try await service.submitMemberRequest(slug: "fab-lab-kochi", items: [.init(product_id: 1, quantity: 2)], purpose: "A project", idempotencyKey: "reviewed-attempt")
            XCTAssertEqual(receipt.public_token, token); XCTAssertEqual(receipt.status, "pending")
            let renewal = try await service.renewMemberLoan(id: 7, requestID: 4); XCTAssertEqual(renewal.renewal_count, 2)
            let availability = try await service.bookingAvailability(slug: "fab-lab-kochi", token: token, start: now, end: now.addingTimeInterval(3600)); XCTAssertNil(availability.availability)
            let booked = try await service.createMemberBooking(slug: "fab-lab-kochi", token: token, input: .init(starts_at: now, ends_at: now.addingTimeInterval(3600)))
            XCTAssertTrue(booked.pending)
            let cancelledBooking = try await service.cancelMemberBooking(slug: "fab-lab-kochi", token: token)
            XCTAssertEqual(cancelledBooking.public_token, token); XCTAssertEqual(cancelledBooking.status.value1.rawValue, "cancelled"); XCTAssertFalse(cancelledBooking.can_cancel)
            let registered = try await service.registerMemberEvent(slug: "fab-lab-kochi", token: token, input: .init(ticket_type_id: 1)); XCTAssertEqual(registered.status.value1, .waitlisted)
            let cancelled = try await service.cancelMemberEvent(id: 7, registration: 77); XCTAssertEqual(cancelled.status.value1, .cancelled)
            let qr = try await service.memberEventQR(id: 7, registration: 77); XCTAssertTrue(String(decoding: qr, as: UTF8.self).contains("<svg"))
            _ = try await service.memberProfile(id: 7)
            _ = try await service.updateMemberProfile(id: 7, input: .init(display_name: "Meera Maker"))
            _ = try await service.communicationPreferences(id: 7)
            _ = try await service.updateCommunicationPreference(id: 7, input: .init(feature: .hardware_requests, channel: .email, enabled: false))
        }
        XCTAssertEqual(calls, 13)
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        XCTFail("The generated JSON request body is missing"); return [:]
    }
}
