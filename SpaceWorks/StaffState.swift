import Foundation
import Observation
import SpaceWorksAPI

/// View state belongs to one authenticated makerspace. Its owner invalidates it before switching scope.
@MainActor @Observable
final class StaffState {
    enum Load: Equatable { case idle, loading, ready, failed(String) }
    let repository: any StaffRepository
    let makerspaceID: Int
    let actions: Set<String>
    let features: Set<String>
    var queue = StaffQueue.pending
    private(set) var requests: [Components.Schemas.AdminRequest] = []
    private(set) var directLoans: [Components.Schemas.DirectLoan] = []
    private(set) var events: [Components.Schemas.EventAdmin] = []
    private(set) var spaces: [Components.Schemas.BookableSpaceAdmin] = []
    private(set) var bookings: [Components.Schemas.BookingAdmin] = []
    private(set) var load = Load.idle
    private(set) var directLoad = Load.idle
    private(set) var eventsLoad = Load.idle
    private(set) var spacesLoad = Load.idle
    private(set) var bookingsLoad = Load.idle
    private(set) var busy = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var retryAfter = Date.distantPast
    private(set) var nextQueuePage: Int?
    private(set) var nextDirectPage: Int?
    private(set) var nextEventPage: Int?
    private(set) var nextSpacePage: Int?
    private(set) var nextBookingPage: Int?
    private var queueGeneration = 0
    private var bookingsGeneration = 0
    private var selectedSpace: Int?
    private var active = true
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    // Destination construction registers weak cleanup callbacks, which must not invalidate views.
    @ObservationIgnored private var children: [() -> Void] = []
    init(repository: any StaffRepository, makerspaceID: Int, actions: Set<String>, features: Set<String>) {
        self.repository = repository; self.makerspaceID = makerspaceID
        self.actions = actions; self.features = features
    }
    var isDemo: Bool { repository.isDemo }
    var isActive: Bool { active }
    var canRequest: Bool { active && !busy && Date() >= retryAfter }
    func can(_ action: String) -> Bool { active && actions.contains(action) }
    var canIssue: Bool { can("issue_request") && can("assign_box") && can("upload_evidence") }
    var canReturn: Bool { can("return_request") && can("upload_evidence") }
    func registerChild(_ invalidate: @escaping () -> Void) { if active { children.append(invalidate) } else { invalidate() } }
    func invalidate() {
        active = false; queueGeneration += 1; bookingsGeneration += 1; cooldownTask?.cancel(); cooldownTask = nil
        children.forEach { $0() }; children = []
        requests = []; directLoans = []; events = []; spaces = []; bookings = []
        error = nil; notice = nil; busy = false
    }
    func loadQueue(more: Bool = false) async {
        guard active, Date() >= retryAfter, !more || (nextQueuePage != nil && load != .loading) else { return }
        queueGeneration += 1; let generation = queueGeneration; let selected = queue
        let page = more ? (nextQueuePage ?? 1) : 1
        load = .loading; if !more { requests = []; nextQueuePage = nil }
        do {
            let result = try await repository.requests(queue: selected, page: page)
            guard active, generation == queueGeneration, selected == queue else { return }
            nextQueuePage = try StaffPaging.next(result.next, after: page)
            requests = StaffPaging.unique((more ? requests : []) + result.results, id: { $0.id })
            load = .ready
        } catch { guard active, generation == queueGeneration else { return }; refuse(error); load = .failed(APIError.display(error)) }
    }
    func accept(_ row: Components.Schemas.AdminRequest, quantities: [Int: Int]) async {
        guard can("accept_request"), row.makerspace_id == makerspaceID,
              row.items.allSatisfy({ $0.requested_quantity >= 0 && (0...$0.requested_quantity).contains(quantities[$0.id] ?? 0) }),
              quantities.values.contains(where: { $0 > 0 }) else { error = "Choose a valid quantity for at least one item."; return }
        let body = Components.Schemas.AcceptRequest(accepted_quantities: row.items.map { .init(item_id: $0.id, quantity: quantities[$0.id] ?? 0) })
        await mutate("Request accepted.") { _ = try await self.repository.accept(id: row.id, body: body) }
    }
    func reject(_ row: Components.Schemas.AdminRequest, reason: String) async {
        let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard can("reject_request"), row.makerspace_id == makerspaceID, !value.isEmpty else { error = "Add a reason before rejecting this request."; return }
        await mutate("Request rejected.") { _ = try await self.repository.reject(id: row.id, body: .init(reason: value)) }
    }
    private func mutate(_ success: String, operation: () async throws -> Void) async {
        guard canRequest else { return }; busy = true; error = nil; notice = nil
        do { try await operation(); guard active else { return }; notice = success; busy = false; await loadQueue() }
        catch { guard active else { return }; refuse(error); self.error = APIError.display(error); busy = false }
    }
    func loadDirect(more: Bool = false) async {
        guard active, Date() >= retryAfter, directLoad != .loading, !more || nextDirectPage != nil else { return }
        let page = more ? nextDirectPage! : 1; directLoad = .loading
        do {
            let result = try await repository.directLoans(page: page); guard active else { return }
            nextDirectPage = try StaffPaging.next(result.next, after: page)
            directLoans = StaffPaging.unique((more ? directLoans : []) + result.results, id: { $0.id }); directLoad = .ready
        } catch { guard active else { return }; refuse(error); directLoad = .failed(APIError.display(error)) }
    }
    func loadEvents(more: Bool = false) async {
        guard active, Date() >= retryAfter, eventsLoad != .loading, !more || nextEventPage != nil else { return }
        let page = more ? nextEventPage! : 1; eventsLoad = .loading
        do {
            let result = try await repository.events(page: page); guard active else { return }
            nextEventPage = try StaffPaging.next(result.next, after: page)
            events = StaffPaging.unique((more ? events : []) + result.results, id: { $0.id }); eventsLoad = .ready
        } catch { guard active else { return }; refuse(error); eventsLoad = .failed(APIError.display(error)) }
    }
    func loadSpaces(more: Bool = false) async {
        guard active, Date() >= retryAfter, spacesLoad != .loading, !more || nextSpacePage != nil else { return }
        let page = more ? nextSpacePage! : 1; spacesLoad = .loading
        do {
            let result = try await repository.spaces(page: page); guard active else { return }
            nextSpacePage = try StaffPaging.next(result.next, after: page)
            spaces = StaffPaging.unique((more ? spaces : []) + result.results, id: { $0.id }); spacesLoad = .ready
        } catch { guard active else { return }; refuse(error); spacesLoad = .failed(APIError.display(error)) }
    }
    func loadBookings(spaceID: Int, more: Bool = false) async {
        guard active, Date() >= retryAfter, !more || (selectedSpace == spaceID && nextBookingPage != nil && bookingsLoad != .loading) else { return }
        bookingsGeneration += 1; let generation = bookingsGeneration
        let page = more ? (nextBookingPage ?? 1) : 1; selectedSpace = spaceID
        bookingsLoad = .loading; if !more { bookings = []; nextBookingPage = nil }
        do {
            let result = try await repository.bookings(spaceID: spaceID, page: page)
            guard active, generation == bookingsGeneration else { return }
            nextBookingPage = try StaffPaging.next(result.next, after: page)
            bookings = StaffPaging.unique((more ? bookings : []) + result.results, id: { $0.id }); bookingsLoad = .ready
        } catch { guard active, generation == bookingsGeneration else { return }; refuse(error); bookingsLoad = .failed(APIError.display(error)) }
    }
    func decideBooking(_ row: Components.Schemas.BookingAdmin, approve: Bool) async {
        guard can("manage_bookings"), canRequest, row.status.value1.rawValue == "pending", selectedSpace == row.space_id else { return }
        busy = true; error = nil; notice = nil
        let scopeGeneration = bookingsGeneration
        do {
            let updated: Components.Schemas.BookingAdmin
            if approve { updated = try await repository.approveBooking(id: row.id) }
            else { updated = try await repository.rejectBooking(id: row.id) }
            busy = false
            guard active, scopeGeneration == bookingsGeneration, selectedSpace == row.space_id else { return }
            bookings = bookings.map { $0.id == updated.id ? updated : $0 }
            notice = approve ? "Booking approved." : "Booking rejected."; busy = false
        } catch {
            guard active else { return }; refuse(error); self.error = APIError.display(error); busy = false
            if active, scopeGeneration == bookingsGeneration, selectedSpace == row.space_id { await loadBookings(spaceID: row.space_id) }
        }
    }
    func refuse(_ error: Error) {
        if let deadline = APIError.retryDeadline(error), deadline > retryAfter {
            retryAfter = deadline; cooldownTask?.cancel()
            cooldownTask = Task { [weak self] in
                let delay = max(0, deadline.timeIntervalSinceNow)
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
                guard let self, self.active else { return }; self.retryAfter = .distantPast
            }
        }
        if [401, 403].contains(APIError.status(error)) {
            invalidate(); self.error = APIError.display(error)
            notice = "Your access changed. Return to your makerspace before continuing."
        }
    }
}

enum StaffPaging {
    static func next(_ raw: String?, after page: Int) throws -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let parts = URLComponents(string: raw), let items = parts.queryItems,
              items.filter({ $0.name == "page" }).count == 1,
              let value = items.first(where: { $0.name == "page" })?.value,
              let next = Int(value), next > page else {
            throw APIError(status: 0, code: "invalid_next_page", detail: "The next page is unavailable. Refresh and try again.")
        }
        return next
    }
    static func unique<T>(_ rows: [T], id: (T) -> Int) -> [T] {
        var seen = Set<Int>(); return rows.filter { seen.insert(id($0)).inserted }
    }
}
