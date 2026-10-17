import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class BookingState {
    let repository: any MemberActionsRepository
    let space: Components.Schemas.PublicBookableSpace
    var start = Date().addingTimeInterval(3600) { didSet { if oldValue != start { changed() } } }
    var end = Date().addingTimeInterval(7200) { didSet { if oldValue != end { changed() } } }
    private(set) var availability: Components.Schemas.PublicSpaceAvailability?
    private(set) var result: Components.Schemas.PublicBookingResponse?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private var generation = 0
    private var active = true
    init(repository: any MemberActionsRepository, space: Components.Schemas.PublicBookableSpace) { self.repository = repository; self.space = space }
    private func valid(now: Date) -> Bool {
        guard end > now, end > start else { error = String(localized: "Choose an end time in the future and after the start time."); return false }
        return true
    }
    func check(now: Date = Date()) async {
        guard active, !busy, (retryAfter ?? .distantPast) <= now, valid(now: now) else { return }
        busy = true; error = nil; availability = nil; result = nil; let expected = generation
        defer { busy = false }
        do {
            let response = try await repository.availability(space: space.public_token, start: start, end: end)
            guard active, expected == generation else { return }; availability = response
        } catch {
            guard active, expected == generation else { return }; self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error)
        }
    }
    func confirm(input: Components.Schemas.PublicBookingInput? = nil, now: Date = Date()) async {
        guard active, !busy, availability != nil, (retryAfter ?? .distantPast) <= now, valid(now: now) else { return }
        var submission = input ?? .init(starts_at: start, ends_at: end)
        submission.starts_at = start; submission.ends_at = end
        busy = true; error = nil; let expected = generation
        defer { busy = false }
        do {
            let response = try await repository.book(space: space.public_token, input: submission)
            guard active, expected == generation else { return }; result = response
        } catch {
            guard active, expected == generation else { return }; self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error)
            if [409, 423, 503].contains(APIError.status(error) ?? 0) { availability = nil }
        }
    }
    func startAnother() {
        guard active, !busy else { return }; start = Date().addingTimeInterval(3600); end = Date().addingTimeInterval(7200)
        availability = nil; result = nil; error = nil
    }
    func invalidate() { active = false; generation += 1; availability = nil; result = nil; error = nil }
    private func changed() { generation += 1; availability = nil; result = nil; error = nil }
}
