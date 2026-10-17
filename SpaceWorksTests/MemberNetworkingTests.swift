import XCTest
import Foundation
import SpaceWorksAPI
@testable import SpaceWorks

final class MemberNetworkingTests: XCTestCase {
    private func first(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let rows = (object as? [[String: Any]]) ?? ((object as! [String: Any])["results"] as! [[String: Any]])
        return String(decoding: try JSONSerialization.data(withJSONObject: rows[0]), as: UTF8.self)
    }
    private func service(handler: @escaping (URLRequest) throws -> String) throws -> SpaceWorksService {
        StubProtocol.lock.lock()
        StubProtocol.handler = { request in (200, ["Content-Type": "application/json"], Data(try handler(request).utf8)) }
        StubProtocol.lock.unlock()
        let config = DeviceSession.configuration(); config.protocolClasses = [StubProtocol.self]
        return SpaceWorksService(origin: try ServerOrigin("https://spaceworks.example"), session: DeviceSession.make(configuration: config),
                                 initialTokens: TokenPair(access: "member-access", refresh: "member-refresh"))
    }
    func testEveryMemberReadAndInboxMutationUsesGeneratedRouteAndSelectedHeader() async throws {
        var paths = Set<String>()
        var calls = 0
        let product = try first(DebugMemberFixtures.inventory)
        let event = try first(DebugMemberFixtures.events)
        let message = try first(DebugMemberFixtures.inbox)
        let eventToken = (try JSONSerialization.jsonObject(with: Data(event.utf8)) as! [String: Any])["public_token"] as! String
        let client = try service { request in
            XCTAssertEqual(request.url?.host, "spaceworks.example")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer member-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Makerspace-Id"), "7")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie")); XCTAssertNil(request.value(forHTTPHeaderField: "X-Publishable-Key"))
            let path = request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            paths.insert(path)
            calls += 1
            switch path {
            case _ where path.hasSuffix("inventory/categories"): return DebugMemberFixtures.categories
            case _ where path.hasSuffix("inventory"):
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)!.queryItems!
                XCTAssertEqual(query.first(where: { $0.name == "page" })?.value, "1")
                XCTAssertEqual(query.first(where: { $0.name == "q" })?.value, "multimeter")
                XCTAssertEqual(query.first(where: { $0.name == "category" })?.value, "electronics")
                return DebugMemberFixtures.inventory
            case _ where path.contains("/inventory/"): return product
            case _ where path.hasSuffix("activity"): return DebugMemberFixtures.activity
            case _ where path.hasSuffix("my-bookings"): return DebugMemberFixtures.bookings
            case _ where path.hasSuffix("events"): return DebugMemberFixtures.events
            case _ where path.contains("/events/"): return event
            case _ where path.hasSuffix("spaces"): return DebugMemberFixtures.spaces
            case _ where path.hasSuffix("member-card"): return DebugMemberFixtures.card
            case _ where path.hasSuffix("unread-count"): return #"{"count":1}"#
            case _ where path.hasSuffix("read-all"):
                XCTAssertEqual(request.httpMethod, "POST"); return #"{"updated":1}"#
            case _ where path.hasSuffix("read"):
                XCTAssertEqual(request.httpMethod, "POST"); return message
            case _ where path.hasSuffix("inbox/7"): return DebugMemberFixtures.inbox
            default: XCTFail("Unexpected generated operation: \(path)"); return "{}"
            }
        }
        try await client.makerspace.select(7, activeMemberships: [7, 9])
        _ = try await client.memberInventory(slug: "makerspace-one", page: 1, search: "multimeter", category: "electronics")
        _ = try await client.memberProduct(slug: "makerspace-one", id: 1)
        _ = try await client.memberCategories(slug: "makerspace-one")
        _ = try await client.memberActivity(id: 7)
        _ = try await client.memberBookings(slug: "makerspace-one", page: 1)
        _ = try await client.memberEvents(slug: "makerspace-one")
        _ = try await client.memberEvent(slug: "makerspace-one", token: eventToken)
        _ = try await client.memberSpaces(slug: "makerspace-one")
        _ = try await client.memberCard(id: 7)
        _ = try await client.memberInbox(id: 7, page: 1, unread: true)
        try await client.memberMarkRead(id: 7, message: 1)
        try await client.memberMarkAllRead(id: 7)
        _ = try await client.memberUnreadCount(id: 7)
        XCTAssertEqual(paths.count, 13)
        XCTAssertEqual(calls, 13)
        try await client.makerspace.select(9, activeMemberships: [7, 9])
        do {
            _ = try await client.withMakerspace(7) { try await client.memberActivity(id: 7) }
            XCTFail("An old repository must not send its path with a new makerspace header")
        } catch {}
        XCTAssertEqual(paths.count, 13)
        XCTAssertEqual(calls, 13, "A context mismatch must fail before transport")
    }
    func testLiveRepositoryRejectsCrossOriginPaginationWithoutFollowingIt() async throws {
        let client = try service { _ in
            DebugMemberFixtures.inventory.replacingOccurrences(of: "\"next\": null", with: "\"next\": \"https://other.example/api/v1/inventory/?page=2\"")
        }
        try await client.makerspace.select(7, activeMemberships: [7])
        let repository = LiveMemberRepository(service: client, expectedCredentials: await client.refresh.snapshot(), origin: try ServerOrigin("https://spaceworks.example"), id: 7, slug: "makerspace-one")
        do { _ = try await repository.inventory(page: 1, search: "", category: nil); XCTFail("Cross-origin next URL was accepted") }
        catch { XCTAssertEqual(APIError.code(error), "invalid_next_page") }
    }
}
