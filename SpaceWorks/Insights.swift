import Foundation
import Observation
import OpenAPIRuntime
import SpaceWorksAPI

/// One labelled point of a server series; `value` is the server's number as text, never recomputed.
struct UsagePoint: Equatable, Sendable { let label: String; let value: String; let amount: Double }
/// A server series reduced to its declared x field and first measure. No points means table-only.
struct UsageSeries: Equatable, Sendable {
    let points: [UsagePoint]
    let unit: String
    let summary: String
    static func from(_ series: Components.Schemas.MemberUsageSeries) -> UsageSeries {
        let x = series.chart_spec.x.field
        guard let measure = series.chart_spec.values.first else { return .init(points: [], unit: "", summary: series.chart_spec.alt_template) }
        let points: [UsagePoint] = series.rows.compactMap { row in
            guard let label = text(row.additionalProperties[x]), let raw = text(row.additionalProperties[measure.field]),
                  let amount = Double(raw) else { return nil }
            return UsagePoint(label: label, value: raw, amount: amount)
        }
        return .init(points: points, unit: measure.unit, summary: series.chart_spec.alt_template)
    }
    static func text(_ value: OpenAPIValueContainer?) -> String? {
        switch value?.value {
        case let text as String: return text
        case let number as Int: return String(number)
        case let number as Double: return number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        default: return nil
        }
    }
}

struct StaffCounter: Equatable, Sendable { let key: String; let value: Int }
struct StaffWidget: Equatable, Sendable { let key: String; let title: String; let headline: String? }
struct StaffGlance: Equatable, Sendable {
    let handover: Bool
    let counters: [StaffCounter]
    let queue: [StaffCounter]
    let widgets: [StaffWidget]
    let outstanding: [(currency: String, amount: String)]
    static func == (lhs: StaffGlance, rhs: StaffGlance) -> Bool {
        lhs.handover == rhs.handover && lhs.counters == rhs.counters && lhs.queue == rhs.queue && lhs.widgets == rhs.widgets
            && lhs.outstanding.map(\.currency) == rhs.outstanding.map(\.currency) && lhs.outstanding.map(\.amount) == rhs.outstanding.map(\.amount)
    }
    /// Omitted counters are unavailable to this actor; only server-reported non-zero counters are shown.
    static func from(_ value: Components.Schemas.Dashboard) -> StaffGlance {
        let counters: [(String, Int?)] = [
            ("pending_requests", value.pending_requests), ("awaiting_issue", value.awaiting_issue), ("overdue_loans", value.overdue_loans),
            ("pending_bookings", value.pending_bookings), ("upcoming_bookings", value.upcoming_bookings), ("upcoming_events", value.upcoming_events),
            ("pending_event_registrations", value.pending_event_registrations), ("open_problem_reports", value.open_problem_reports),
            ("low_stock", value.low_stock), ("pending_prints", value.pending_prints), ("active_prints", value.active_prints),
            ("prints_awaiting_collection", value.prints_awaiting_collection), ("maintenance_overdue", value.maintenance_overdue),
            ("warranty_expiring", value.warranty_expiring), ("stocktakes_awaiting_approval", value.stocktakes_awaiting_approval),
            ("pending_payments", value.pending_payments), ("failed_emails", value.failed_emails)]
        let queue = value.queue_tiles.map { tiles in
            [("ready_to_issue", tiles.ready_to_issue), ("due_returns", tiles.due_returns), ("pickups", tiles.pickups)]
                .compactMap { key, count in count.map { StaffCounter(key: key, value: $0) } }
        } ?? []
        let handover = value.scope_mode == .handover
        let widgets = handover ? [] : (value.widgets ?? []).map { widget in
            StaffWidget(key: widget.key, title: widget.title,
                        headline: ["count", "total", "value"].lazy.compactMap { UsageSeries.text(widget.data.additionalProperties[$0]) }.first { Double($0) != nil })
        }
        return StaffGlance(handover: handover,
            counters: counters.compactMap { key, count in count.flatMap { $0 > 0 ? StaffCounter(key: key, value: $0) : nil } },
            queue: queue, widgets: widgets,
            outstanding: (value.outstanding_by_currency?.additionalProperties ?? [:]).sorted { $0.key < $1.key }.map { ($0.key.uppercased(), $0.value) })
    }
    static func label(_ key: String) -> String {
        switch key {
        case "pending_requests": return String(localized: "Pending requests")
        case "awaiting_issue": return String(localized: "Awaiting issue")
        case "overdue_loans": return String(localized: "Overdue loans")
        case "pending_bookings": return String(localized: "Pending bookings")
        case "upcoming_bookings": return String(localized: "Upcoming bookings")
        case "upcoming_events": return String(localized: "Upcoming events")
        case "pending_event_registrations": return String(localized: "Pending event registrations")
        case "open_problem_reports": return String(localized: "Open problem reports")
        case "low_stock": return String(localized: "Low stock")
        case "pending_prints": return String(localized: "Pending prints")
        case "active_prints": return String(localized: "Active prints")
        case "prints_awaiting_collection": return String(localized: "Prints awaiting collection")
        case "maintenance_overdue": return String(localized: "Maintenance overdue")
        case "warranty_expiring": return String(localized: "Warranty expiring")
        case "stocktakes_awaiting_approval": return String(localized: "Stocktakes awaiting approval")
        case "pending_payments": return String(localized: "Pending payments")
        case "failed_emails": return String(localized: "Failed emails")
        case "ready_to_issue": return String(localized: "Ready to issue")
        case "due_returns": return String(localized: "Due back")
        case "pickups": return String(localized: "Pickups")
        default: return key
        }
    }
}

protocol InsightsRepository: Sendable {
    func usage() async throws -> Components.Schemas.MemberUsage
    func dashboard() async throws -> Components.Schemas.Dashboard
    func messaging() async throws -> Components.Schemas.MemberMessaging
    func consent(channel: Components.Schemas.Channel06eEnum, optIn: Bool) async throws -> Components.Schemas.MemberMessaging
}

struct LiveInsightsRepository: InsightsRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot?
    let makerspaceID: Int
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
    func usage() async throws -> Components.Schemas.MemberUsage { try await checked { try await service.memberUsage(makerspaceID: makerspaceID) } }
    func dashboard() async throws -> Components.Schemas.Dashboard { try await checked { try await service.staffDashboard(makerspaceID: makerspaceID) } }
    func messaging() async throws -> Components.Schemas.MemberMessaging { try await checked { try await service.messagingConsent(makerspaceID: makerspaceID) } }
    func consent(channel: Components.Schemas.Channel06eEnum, optIn: Bool) async throws -> Components.Schemas.MemberMessaging {
        try await checked { try await service.setMessagingConsent(makerspaceID: makerspaceID, channel: channel, optIn: optIn) }
    }
}

/// Per-session, per-makerspace insight state. The owning workspace invalidates it on switch or sign-out.
@MainActor @Observable
final class InsightsState {
    enum Load<Value: Equatable>: Equatable { case idle, loading, ready(Value), failed(String) }
    private(set) var usage = Load<Components.Schemas.MemberUsage>.idle
    private(set) var dashboard = Load<StaffGlance>.idle
    private(set) var messaging = Load<Components.Schemas.MemberMessaging>.idle
    private(set) var consentBusy: Components.Schemas.Channel06eEnum?
    private(set) var consentError: String?
    private var active = true
    private var retryAfter = Date.distantPast
    private let repository: any InsightsRepository
    private let now: () -> Date
    init(repository: any InsightsRepository, now: @escaping () -> Date = Date.init) { self.repository = repository; self.now = now }

    func refreshUsage() async {
        guard active, usage != .loading, now() >= retryAfter else { return }
        usage = .loading
        do { let value = try await repository.usage(); if active { usage = .ready(value) } }
        catch { if active { usage = failed(error) ?? .idle } }
    }
    func refreshDashboard() async {
        guard active, dashboard != .loading, now() >= retryAfter else { return }
        dashboard = .loading
        do { let value = try await repository.dashboard(); if active { dashboard = .ready(.from(value)) } }
        catch { if active { dashboard = failed(error) ?? .idle } }
    }
    func refreshMessaging() async {
        guard active, messaging != .loading, now() >= retryAfter else { return }
        messaging = .loading
        do { let value = try await repository.messaging(); if active { messaging = .ready(value) } }
        catch { if active { messaging = failed(error) ?? .idle } }
    }
    static func canOptIn(_ channel: Components.Schemas.MessagingChannel) -> Bool {
        channel.available && channel.phone_verified && !channel.suppressed && !channel.consented
    }
    /// The server decides consent; the switch shows its returned state, and any refusal refetches it.
    func setConsent(_ channel: Components.Schemas.Channel06eEnum, optIn: Bool) async {
        guard active, consentBusy == nil, now() >= retryAfter, case .ready(let current) = messaging else { return }
        let target = channel == .sms ? current.sms : current.whatsapp
        if optIn && !Self.canOptIn(target) { return }
        consentBusy = channel; consentError = nil
        defer { consentBusy = nil }
        do {
            let value = try await repository.consent(channel: channel, optIn: optIn)
            if active { messaging = .ready(value) }
        } catch {
            guard active, !APIError.isCancellation(error) else { return }
            consentError = APIError.display(error)
            if let deadline = APIError.retryDeadline(error) { retryAfter = deadline }
            consentBusy = nil
            messaging = .idle
            await refreshMessaging()
        }
    }
    func invalidate() { active = false; usage = .idle; dashboard = .idle; messaging = .idle; consentError = nil }
    private func failed<T: Equatable>(_ error: Error) -> Load<T>? {
        guard !APIError.isCancellation(error) else { return nil }
        if let deadline = APIError.retryDeadline(error) { retryAfter = deadline }
        return .failed(APIError.display(error))
    }
}
