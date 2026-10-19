import Foundation
import Observation
import SpaceWorksAPI

protocol PushRegistrationRepository: Sendable {
    func register(makerspaceID: Int, token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> Components.Schemas.PushDevice
    func unregister(makerspaceID: Int, deviceID: Int, authorizedDirectMembershipIDs: Set<Int>) async throws
}

struct LivePushRegistrationRepository: PushRegistrationRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot
    func register(makerspaceID: Int, token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> Components.Schemas.PushDevice {
        guard let environment = Components.Schemas.EnvironmentEnum(rawValue: environment) else { throw PushRegistrationCoordinator.invalidConfiguration }
        return try await service.withPushMakerspace(makerspaceID, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs, expectedCredentials: expectedCredentials) {
            try await service.registerNativePush(token: token, environment: environment)
        }
    }
    func unregister(makerspaceID: Int, deviceID: Int, authorizedDirectMembershipIDs: Set<Int>) async throws {
        do {
            try await service.withPushMakerspace(makerspaceID, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs, expectedCredentials: expectedCredentials) {
                try await service.unregisterNativePush(deviceID: deviceID)
            }
        } catch { if APIError.status(error) != 404 { throw error } }
    }
}

/// Explicit serialization spans server suspension. Actor isolation alone would permit interleaving.
actor PushRegistrationCoordinator {
    private let repository: any PushRegistrationRepository
    private let storage: any PushRegistrationStorage
    private var snapshot: PushRegistrationSnapshot?
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var suspendedMakerspaces = Set<Int>()
    init(repository: any PushRegistrationRepository, storage: any PushRegistrationStorage) { self.repository = repository; self.storage = storage }
    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
    private func value() throws -> PushRegistrationSnapshot {
        if let snapshot { return snapshot }
        let loaded = try storage.load(); snapshot = loaded; return loaded
    }
    private func save(_ value: PushRegistrationSnapshot) throws {
        // Retain new IDs in memory even if Keychain is temporarily unavailable: logout can clean them.
        snapshot = value
        try storage.store(value)
    }
    func load() async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        return try value()
    }
    func enable(token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        guard Self.validToken(token), ["development", "production"].contains(environment), authorizedDirectMembershipIDs.allSatisfy({ $0 > 0 }) else { throw Self.invalidConfiguration }
        suspendedMakerspaces.subtract(authorizedDirectMembershipIDs)
        var state = try value()
        state.enabled = true
        try save(state)
        return try await reconcileLocked(token: token, environment: environment, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
    }
    func reconcile(token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        return try await reconcileLocked(token: token, environment: environment, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
    }
    private func reconcileLocked(token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async throws -> PushRegistrationSnapshot {
        var state = try value()
        guard state.enabled else { return state }
        guard Self.validToken(token), ["development", "production"].contains(environment), authorizedDirectMembershipIDs.allSatisfy({ $0 > 0 }) else { throw Self.invalidConfiguration }
        try Task.checkCancellation()
        let digest = PushRegistrationVault.digest(token.lowercased())
        // A removed membership can no longer authorize deletion. Its routing is already refused;
        // owner calls removeMembership BEFORE a voluntary leave while that scope is still valid.
        state.registrations.removeAll { !authorizedDirectMembershipIDs.contains($0.makerspaceID) }
        try save(state)
        for maker in authorizedDirectMembershipIDs.subtracting(suspendedMakerspaces).sorted() {
            try Task.checkCancellation()
            if let old = state.registrations.first(where: { $0.makerspaceID == maker }) {
                if old.tokenDigest == digest && old.environment == environment && !old.pendingDeletion { continue }
                try await repository.unregister(makerspaceID: maker, deviceID: old.deviceID, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
                state.registrations.removeAll { $0.makerspaceID == maker }
                try save(state)
            }
            let registered = try await repository.register(makerspaceID: maker, token: token.lowercased(), environment: environment, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
            guard registered.id > 0, registered.makerspace_id == maker, registered.provider == "apns", registered.environment == environment, registered.active else {
                throw APIError(status: 0, code: "invalid_push_registration", detail: String(localized: "The server could not confirm notification registration. Your inbox is still available."))
            }
            state.registrations.append(.init(makerspaceID: maker, deviceID: registered.id, tokenDigest: digest, environment: environment))
            do { try save(state) }
            catch {
                // A newly returned server ID must not disappear just because persistence failed.
                // Attempt immediate cleanup; keep the pending ID for a later authorized retry.
                let failure = error
                if let index = state.registrations.firstIndex(where: { $0.makerspaceID == maker }) { state.registrations[index].pendingDeletion = true }
                snapshot = state
                do {
                    try await repository.unregister(makerspaceID: maker, deviceID: registered.id, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
                    state.registrations.removeAll { $0.makerspaceID == maker }; snapshot = state
                    try? storage.store(state)
                } catch { throw Self.preferredFailure(failure, error) }
                throw failure
            }
        }
        return state
    }
    /// Use before membership revocation. The real direct-membership set still has to include it.
    func removeMembership(_ makerspaceID: Int, authorizedDirectMembershipIDs: Set<Int>) async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        var state = try value()
        guard authorizedDirectMembershipIDs.contains(makerspaceID) else { throw CancellationError() }
        suspendedMakerspaces.insert(makerspaceID)
        guard let row = state.registrations.first(where: { $0.makerspaceID == makerspaceID }) else { return state }
        if let index = state.registrations.firstIndex(where: { $0.makerspaceID == makerspaceID }) { state.registrations[index].pendingDeletion = true }
        try save(state)
        try await repository.unregister(makerspaceID: makerspaceID, deviceID: row.deviceID, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
        state.registrations.removeAll { $0.makerspaceID == makerspaceID }
        try save(state)
        return state
    }
    /// Only after a failed leave and a fresh identity response confirms that membership remains.
    func resumeMembership(_ makerspaceID: Int, authorizedDirectMembershipIDs: Set<Int>) async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        guard authorizedDirectMembershipIDs.contains(makerspaceID) else { throw CancellationError() }
        suspendedMakerspaces.remove(makerspaceID)
        return try value()
    }
    /// Best effort before token/grant removal. Failed deletes remain pending, never active/deduped.
    func stop(authorizedDirectMembershipIDs: Set<Int>, preserveConsent: Bool) async throws -> PushRegistrationSnapshot {
        await acquire(); defer { release() }
        var state = try value()
        if !preserveConsent { state.enabled = false }
        state.registrations = state.registrations.map { var row = $0; row.pendingDeletion = true; return row }
        var firstError: Error?
        do { try save(state) } catch { firstError = error }
        for row in state.registrations {
            if !authorizedDirectMembershipIDs.contains(row.makerspaceID) {
                state.registrations.removeAll { $0.makerspaceID == row.makerspaceID }
                do { try save(state) } catch { firstError = Self.preferredFailure(firstError, error) }
                continue
            }
            do {
                try await repository.unregister(makerspaceID: row.makerspaceID, deviceID: row.deviceID, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs)
                state.registrations.removeAll { $0.makerspaceID == row.makerspaceID }
                try save(state)
            } catch {
                firstError = Self.preferredFailure(firstError, error)
                if [401, 429].contains(APIError.status(error) ?? 0) || PushOperationFailure.isCancellation(error) { break }
            }
        }
        if let firstError { throw firstError }
        return state
    }
    /// Storage failure must not hide an API deadline or revoked authentication from the owner.
    private static func preferredFailure(_ existing: Error?, _ incoming: Error) -> Error {
        guard let existing else { return incoming }
        func priority(_ error: Error) -> Int {
            switch APIError.status(error) {
            case 401: return 4
            case 429: return 3
            case 403: return 2
            case .some(let status) where status >= 400: return 1
            default: return 0
            }
        }
        return priority(incoming) > priority(existing) ? incoming : existing
    }
    static func validToken(_ token: String) -> Bool {
        token.utf8.count >= 20 && token.utf8.count <= 4096 && token.count.isMultiple(of: 2) && token.allSatisfy { "0123456789abcdefABCDEF".contains($0) }
    }
    static var invalidConfiguration: APIError { APIError(status: 0, code: "push_not_configured", detail: String(localized: "Notifications are not configured for this build. Your inbox is still available.")) }
}

@MainActor @Observable final class PushRegistrationState {
    let configured: Bool
    let isDemo: Bool
    private let coordinator: PushRegistrationCoordinator
    private let onUnauthorized: @Sendable (String) async -> Void
    private let onForbidden: @Sendable () async -> Void
    private var active = true
    private var pausing = false
    private var generation = 0
    private var calls = 0
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    private(set) var enabled = false
    private(set) var registeredMakerspaces = Set<Int>()
    private(set) var error: String?
    private(set) var retryAfter = Date.distantPast
    var busy: Bool { calls > 0 }
    var canRequest: Bool { active && !pausing && configured && !isDemo && Date() >= retryAfter }
    init(repository: any PushRegistrationRepository, storage: any PushRegistrationStorage, configured: Bool, isDemo: Bool = false,
         onUnauthorized: @escaping @Sendable (String) async -> Void = { _ in }, onForbidden: @escaping @Sendable () async -> Void = {}) {
        coordinator = PushRegistrationCoordinator(repository: repository, storage: storage)
        self.configured = configured; self.isDemo = isDemo; self.onUnauthorized = onUnauthorized; self.onForbidden = onForbidden
    }
    func load() async { guard active, !isDemo else { return }; await perform { try await self.coordinator.load() } }
    func enable(token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async {
        guard active else { return }
        guard configured, !isDemo else { error = PushRegistrationCoordinator.invalidConfiguration.detail; return }
        guard !pausing, Date() >= retryAfter else { return }
        await perform { try await self.coordinator.enable(token: token, environment: environment, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs) }
    }
    func synchronize(token: String, environment: String, authorizedDirectMembershipIDs: Set<Int>) async {
        guard canRequest else { return }
        await perform { try await self.coordinator.reconcile(token: token, environment: environment, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs) }
    }
    func disable(authorizedDirectMembershipIDs: Set<Int>) async {
        guard active, !pausing, !isDemo, Date() >= retryAfter else { return }
        await perform { try await self.coordinator.stop(authorizedDirectMembershipIDs: authorizedDirectMembershipIDs, preserveConsent: false) }
    }
    /// OS permission can be revoked outside the app. Remove server routing while retaining
    /// account consent so a later permission restoration can synchronize this same state.
    func pause(authorizedDirectMembershipIDs: Set<Int>) async {
        guard canRequest else { return }
        pausing = true
        defer { pausing = false }
        await perform { try await self.coordinator.stop(authorizedDirectMembershipIDs: authorizedDirectMembershipIDs, preserveConsent: true) }
    }
    @discardableResult func removeMembership(_ id: Int, authorizedDirectMembershipIDs: Set<Int>) async -> Bool {
        guard active, !pausing, !isDemo, Date() >= retryAfter, authorizedDirectMembershipIDs.contains(id) else { return false }
        return await perform { try await self.coordinator.removeMembership(id, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs) }
    }
    func resumeMembership(_ id: Int, authorizedDirectMembershipIDs: Set<Int>) async {
        // This only removes a local suspension after fresh identity confirmation. It sends no
        // request; keeping the existing deadline still blocks the next reconcile/API mutation.
        guard active, !pausing, !isDemo else { return }
        await perform { try await self.coordinator.resumeMembership(id, authorizedDirectMembershipIDs: authorizedDirectMembershipIDs) }
    }
    /// Await this before wiping credentials; it also waits for any registration currently in flight.
    /// Suppress auth callbacks here: the owning auth transition is already ending the session.
    func stop(authorizedDirectMembershipIDs: Set<Int>) async {
        invalidate() // Block new APNs callbacks before waiting for the current transaction.
        guard !isDemo else { return }
        await perform(notifyAuthorization: false) { try await self.coordinator.stop(authorizedDirectMembershipIDs: authorizedDirectMembershipIDs, preserveConsent: true) }
    }
    func invalidate() {
        active = false; generation += 1; enabled = false; registeredMakerspaces = []; error = nil
        cooldownTask?.cancel(); cooldownTask = nil
    }
    private func publish(_ value: PushRegistrationSnapshot) {
        enabled = value.enabled
        registeredMakerspaces = Set(value.registrations.filter { !$0.pendingDeletion }.map(\.makerspaceID))
    }
    @discardableResult private func perform(notifyAuthorization: Bool = true, _ work: () async throws -> PushRegistrationSnapshot) async -> Bool {
        generation += 1; let expected = generation
        calls += 1; error = nil
        var failure: Error?
        var succeeded = false
        do { let value = try await work(); if active, expected == generation { publish(value); succeeded = true } }
        catch {
            failure = error
            if active, expected == generation, !PushOperationFailure.isCancellation(error) {
                self.error = APIError.display(error)
                if let deadline = APIError.retryDeadline(error), deadline > retryAfter {
                    retryAfter = deadline; cooldownTask?.cancel()
                    cooldownTask = Task { [weak self] in
                        do {
                            while Date() < deadline { try await Task.sleep(nanoseconds: UInt64(min(max(0, deadline.timeIntervalSinceNow), 3_600) * 1_000_000_000)) }
                        } catch { return }
                        guard let self, self.retryAfter == deadline, Date() >= deadline else { return }
                        self.retryAfter = .distantPast
                    }
                }
                // Partial registrations/deletions are authoritative even when a later maker fails.
                if ![401, 403].contains(APIError.status(error) ?? 0), let saved = try? await coordinator.load(), active, expected == generation { publish(saved) }
            }
        }
        calls -= 1
        // The coordinator's serial lock has been released before a callback can trigger logout.
        if notifyAuthorization, active, expected == generation, let failure {
            if APIError.status(failure) == 401 { await onUnauthorized(APIError.display(failure)) }
            else if APIError.status(failure) == 403 { await onForbidden() }
        }
        return succeeded && active && expected == generation
    }
}
