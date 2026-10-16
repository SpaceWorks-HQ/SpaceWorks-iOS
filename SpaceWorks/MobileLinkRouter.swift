import Foundation
import Observation
import SpaceWorksAPI

/// A hint cannot navigate until fresh identity and selected scope have both succeeded.
@MainActor @Observable final class MobileLinkRouter {
    struct Approved: Identifiable, Equatable {
        let id = UUID()
        let account: String
        let link: MobileLink
        let refetchInbox: Bool
        init(account: String, link: MobileLink, refetchInbox: Bool = false) { self.account = account; self.link = link; self.refetchInbox = refetchInbox }
    }
    private(set) var pending: MobileLink?
    private(set) var pendingLegacy: MobileLink.Legacy?
    var hasPending: Bool { pending != nil || pendingLegacy != nil }
    private(set) var approved: Approved?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private(set) var revision = 0
    private var pendingNeedsInbox = false
    private var bindingRevision = 0
    private var bindingOwner: UUID?
    private var account: String?
    private var refresh: (() async throws -> Set<Int>)?
    private var select: ((Int) async throws -> Void)?
    private var resolveLegacy: ((MobileLink.Legacy) async throws -> MobileLink)?
    func cancelIntent() { pendingNeedsInbox = false; revision += 1; pending = nil; pendingLegacy = nil; approved = nil; error = nil }
    func refuseURL() { cancelIntent(); error = "That link can't be opened in this app." }
    func receive(_ hint: NotificationHint) {
        if hint.version == 2, let path = hint.relativeLink, let legacy = MobileLink.legacy(path) {
            receive(MobileLink.Legacy(slug: legacy.slug, staffInbox: legacy.staffInbox, expectedMakerspaceID: hint.makerspaceID))
        } else { receive(MobileLink.notification(hint)) }
        pendingNeedsInbox = true
    }
    func receive(_ link: MobileLink) { pendingNeedsInbox = false; revision += 1; pendingLegacy = nil; pending = link; approved = nil; error = nil }
    func receive(_ legacy: MobileLink.Legacy) { pendingNeedsInbox = false; revision += 1; pending = nil; pendingLegacy = legacy; approved = nil; error = nil }
    func bind(account: String, refresh: @escaping () async throws -> Set<Int>, select: @escaping (Int) async throws -> Void, resolveLegacy: ((MobileLink.Legacy) async throws -> MobileLink)? = nil, owner: UUID? = nil) {
        if let previous = self.account, previous != account || bindingOwner != owner { bindingRevision += 1; revision += 1; pending = nil; pendingLegacy = nil; approved = nil; retryAfter = nil }
        self.account = account; self.bindingOwner = owner; self.refresh = refresh; self.select = select; self.resolveLegacy = resolveLegacy
    }
    func process(now: Date = Date()) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        while hasPending, let account, let refresh, let select {
            guard (retryAfter ?? .distantPast) <= now else { return }
            let expected = revision; let expectedBinding = bindingRevision; let needsInbox = pendingNeedsInbox; error = nil
            do {
                let intent: MobileLink
                if let legacy = pendingLegacy {
                    guard let resolveLegacy else { throw APIError(status: 403, code: "link_unavailable", detail: "This update isn't available to your account.") }
                    let resolved = try await resolveLegacy(legacy)
                    if let expected = legacy.expectedMakerspaceID, resolved.makerspaceID != expected {
                        intent = MobileLink(makerspaceID: expected, destination: .inbox)
                    } else { intent = resolved }
                } else if let pending { intent = pending } else { return }
                guard self.account == account, bindingRevision == expectedBinding else { continue }
                if revision != expected { continue }
                let membershipIDs = try await refresh()
                guard self.account == account, bindingRevision == expectedBinding else { continue }
                if revision != expected { continue }
                guard membershipIDs.contains(intent.makerspaceID) else { throw APIError(status: 403, code: "link_membership_unavailable", detail: "This makerspace isn't available to your account.") }
                try await select(intent.makerspaceID)
                guard self.account == account, bindingRevision == expectedBinding else { continue }
                if revision != expected { continue }
                pending = nil; pendingLegacy = nil; approved = .init(account: account, link: intent, refetchInbox: needsInbox); pendingNeedsInbox = false; retryAfter = nil
            } catch {
                guard self.account == account, bindingRevision == expectedBinding else { continue }
                if let deadline = APIError.retryDeadline(error) { retryAfter = max(retryAfter ?? .distantPast, deadline) }
                if revision != expected { continue }
                self.error = APIError.display(error); return
            }
        }
    }
    func isCurrent(_ value: Approved) -> Bool { approved?.id == value.id && account == value.account }
    func destinationFailed(_ value: Approved, error: Error) {
        guard isCurrent(value) else { return }
        pendingNeedsInbox = value.refetchInbox; pendingLegacy = nil; pending = value.link; approved = nil; self.error = APIError.display(error)
        if let deadline = APIError.retryDeadline(error) { retryAfter = max(retryAfter ?? .distantPast, deadline) }
    }
    func finish(_ value: Approved) { if isCurrent(value) { approved = nil } }
    func unbind(owner: UUID? = nil) {
        if let owner, bindingOwner != owner { return }
        if account != nil { pending = nil; pendingLegacy = nil; error = nil; retryAfter = nil }
        if account != nil { pendingNeedsInbox = false }
        bindingRevision += 1; revision += 1; bindingOwner = nil; account = nil; refresh = nil; select = nil; resolveLegacy = nil; approved = nil
    }
    func reset() { unbind(); pendingNeedsInbox = false; pending = nil; pendingLegacy = nil; error = nil; retryAfter = nil }
}
