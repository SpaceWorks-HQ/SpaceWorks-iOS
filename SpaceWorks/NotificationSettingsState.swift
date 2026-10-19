import Foundation
import Observation
import SpaceWorksAPI
import UIKit
import UserNotifications

@MainActor protocol NativePushAccess: AnyObject {
    var authorization: UNAuthorizationStatus { get }
    var token: String? { get }
    var error: String? { get }
    func requestPermission() async
    func refreshAuthorization() async
}
extension NativeNotifications: NativePushAccess {}

@MainActor @Observable final class NotificationSettingsState {
    let registration: PushRegistrationState
    private let native: any NativePushAccess
    private let environment: String
    private let memberships: () async throws -> Set<Int>
    private let settings: () -> Void
    private var active = true
    private var revision = 0
    private var wantsEnable = false
    private var pendingToken: String?
    private var localError: String?
    private var identityRetryAfter = Date.distantPast
    var retryAfter: Date { max(registration.retryAfter, identityRetryAfter) }
    private(set) var busy = false
    var error: String? { localError ?? native.error }
    var permissionDenied: Bool { native.authorization == .denied }
    init(registration: PushRegistrationState, native: any NativePushAccess = NativeNotifications.shared,
         environment: String, memberships: @escaping () async throws -> Set<Int>,
         settings: @escaping () -> Void = { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }) {
        self.registration = registration; self.native = native; self.environment = environment
        self.memberships = memberships; self.settings = settings
    }
    func openSettings() { guard active, registration.configured, !registration.isDemo else { return }; settings() }
    func prepare() async {
        guard active, !busy else { return }
        await registration.load()
        await refresh()
    }
    func refresh() async {
        guard active, !busy, registration.configured, !registration.isDemo, registration.enabled || wantsEnable else { return }
        busy = true; let expected = revision; defer { finishBusy() }
        await native.refreshAuthorization()
        guard active, revision == expected, Date() >= retryAfter else { return }
        if permissionDenied {
            wantsEnable = false
            do { let ids = try await memberships(); guard active, revision == expected else { return }; await registration.pause(authorizedDirectMembershipIDs: ids) }
            catch { if active, revision == expected { record(error) } }
        } else if allowed, let token = native.token { await reconcile(token, expected: expected) }
    }
    func enable() async {
        guard active, !busy, registration.canRequest, Date() >= retryAfter else { return }
        busy = true; let expected = revision; defer { finishBusy() }
        wantsEnable = true; localError = nil
        await native.requestPermission()
        guard active, revision == expected else { return }
        guard allowed else { wantsEnable = false; return }
        if let token = native.token { await reconcile(token, expected: expected) }
        // APNs may supply the token after authorization returns. Only this account's callback may use it.
    }
    func tokenChanged(_ token: String) async {
        guard active, allowed, registration.canRequest, registration.enabled || wantsEnable, Date() >= retryAfter else { return }
        if busy { pendingToken = token; return }
        pendingToken = nil
        busy = true; let expected = revision; defer { finishBusy() }
        await reconcile(token, expected: expected)
    }
    private func finishBusy() {
        busy = false
        if active, let token = pendingToken { pendingToken = nil; Task { await self.tokenChanged(token) } }
    }
    private var allowed: Bool { [.authorized, .provisional, .ephemeral].contains(native.authorization) }
    private func reconcile(_ token: String, expected: Int) async {
        do {
            let ids = try await memberships()
            guard active, revision == expected else { return }
            if wantsEnable { await registration.enable(token: token, environment: environment, authorizedDirectMembershipIDs: ids) }
            else { await registration.synchronize(token: token, environment: environment, authorizedDirectMembershipIDs: ids) }
            if active, revision == expected, registration.enabled { wantsEnable = false }
        } catch { if active, revision == expected { record(error) } }
    }
    func disable() async {
        guard active, !busy, Date() >= retryAfter else { return }
        wantsEnable = false; revision += 1; let expected = revision; busy = true; localError = nil; defer { finishBusy() }
        do { let ids = try await memberships(); guard active, revision == expected else { return }; await registration.disable(authorizedDirectMembershipIDs: ids) }
        catch { if active, revision == expected { record(error) } }
    }
    private func record(_ error: Error) {
        localError = APIError.display(error)
        if let deadline = APIError.retryDeadline(error) { identityRetryAfter = max(identityRetryAfter, deadline) }
    }
    /// An already-replaced account must never use its successor's credentials for cleanup.
    /// Keep its origin/account-scoped registration IDs for cleanup when that owner authenticates again.
    func detach() {
        active = false; revision += 1; wantsEnable = false; pendingToken = nil; localError = nil
        registration.invalidate()
    }
    func stop(authorizedDirectMembershipIDs: Set<Int>) async {
        active = false; revision += 1; wantsEnable = false; pendingToken = nil; localError = nil
        await registration.stop(authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
    }
}
