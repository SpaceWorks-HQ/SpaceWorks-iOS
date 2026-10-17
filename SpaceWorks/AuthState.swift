import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class AuthState {
    enum Stage: Equatable { case restoring, signIn, mfa, recoveryCodes, passwordChange, securityCompletion, signedIn }
    private(set) var stage: Stage = .restoring
    var username = ""
    var password = ""
    var code = ""
    private(set) var busy = false
    private(set) var endingSession = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private(set) var user: Components.Schemas.AuthUserPayload?
    private(set) var mfa: Components.Schemas.MFAChallengeResponse?
    private(set) var enrollment: Components.Schemas.MFAEnrollment?
    private(set) var recoveryCodes: [String] = []
    private(set) var securityMessage: String?
    private var locallyLeftMemberships = Set<Int>()
    private(set) var selectedID: Int?
    private(set) var configuration: Components.Schemas.PublicConfig?
    let service: SpaceWorksService
    private let attest: @Sendable (String) async throws -> Data
    private let settings: UserDefaults
    private let storage: any TokenStorage
    private var restored = false
    private var identityGeneration = 0
    private(set) var acceptedCredentials: CredentialSnapshot?
    private var identityFlight: Task<Void, Error>?
    private var privateHolders: [UUID: () -> Void] = [:]
    private var mfaExpires: Date?
    private let serverScope: String
    private let origin: ServerOrigin
    private(set) var notifications: NotificationSettingsState?
    private(set) var foregroundHintRevision = 0
    private(set) var inboxRefreshRevision = 0
    private(set) var inboxRefreshMakerspaceID: Int?
    private var pendingForegroundHint: (accountID: Int, makerspaceID: Int)?
    private var pushAccountID: Int?
    private let notificationOwnerID = UUID()
    private static var notificationOwner: UUID?

    init(origin: ServerOrigin, session: URLSession = DeploymentSession.make(), settings: UserDefaults = .standard,
         storage: (any TokenStorage)? = nil,
         attest: @escaping @Sendable (String) async throws -> Data = { try await NativeAttestor.attest($0) }) {
        let storage = storage ?? TokenVault(origin: origin)
        self.storage = storage
        self.origin = origin
        self.attest = attest
        self.settings = settings
        self.serverScope = origin.url.absoluteString
        var pair: TokenPair?
        var storageError: String?
        do { pair = try storage.load() } catch { storageError = APIError.display(error) }
        service = SpaceWorksService(origin: origin, session: session, initialTokens: pair, persist: { try storage.store($0) })
        error = storageError
    }
    var memberships: [Components.Schemas.AuthMembership] {
        // Organization-derived authority is excluded by the mobile scope. /me supplies active memberships.
        user?.makerspaces.filter { $0.source == .membership && !locallyLeftMemberships.contains($0.id) } ?? []
    }
    var selectedMembership: Components.Schemas.AuthMembership? { memberships.first { $0.id == selectedID } }
    var displayName: String { user?.display_name.isEmpty == false ? user!.display_name : user?.username ?? "" }
    var passwordEnabled: Bool {
        guard configuration != nil else { return false }
        return configFlag("password_login")
    }
    var signupEnabled: Bool { configuration != nil && configFlag("member_accounts") && configFlag("self_registration") }
    private func configFlag(_ key: String) -> Bool {
        guard let configuration, let data = try? JSONEncoder().encode(configuration),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object[key] as? [String: Any] else { return true }
        // PublicConfig's extensible object; same documented switch consumed by MemberAuthPanel.
        return login["enabled"] as? Bool != false
    }
    // Fail closed until the schema supplies native_staff authority (backend 1a).
    var staffToolsAvailable: Bool { false }
    private var selectionKey: String { "makerspace-selection.\(serverScope).\(user?.id ?? 0)" }
    func retryRestore() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        restored = false; error = nil; await restore()
    }
    func accountForm(_ step: AccountAccessState.Step) -> AccountAccessState {
        let service = service
        let generation = identityGeneration
        let accountID = user?.id
        let credentials = acceptedCredentials
        let task = step == .signUp ? "signup" : step == .emailVerification ? "email" : "password-recovery"
        let scope = serverScope + "." + task + (step == .emailVerification ? ".\(accountID ?? 0)" : "")
        let form = AccountAccessState(step: step, cooldown: AccountAccessCooldown.scoped(scope),
            create: { try await service.createAccount(name: $0, email: $1, password: $2, phone: $3) },
            request: { try await service.requestPasswordReset(email: $0) },
            reset: { try await service.resetPassword(email: $0, code: $1, new: $2) },
            verify: { [weak self] code in
                guard let self else { throw CancellationError() }
                try await self.emailOperation(generation: generation, accountID: accountID, credentials: credentials) {
                    try await service.confirmEmail(code: code)
                }
                await self.foreground()
            },
            resendVerification: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.emailOperation(generation: generation, accountID: accountID, credentials: credentials) {
                    try await service.resendEmailVerification()
                }
            }, ownerIsCurrent: { [weak self] in
                guard step == .emailVerification else { return true }
                guard let self, let accountID else { return false }
                return self.identityGeneration == generation && self.user?.id == accountID && self.stage == .signedIn
            })
        form.email = user?.email ?? username
        return form
    }

    private func emailOperation(generation: Int, accountID: Int?, credentials: CredentialSnapshot?,
                                operation: @Sendable () async throws -> Void) async throws {
        guard let accountID, let credentials,
              identityGeneration == generation, user?.id == accountID, stage == .signedIn else { throw CancellationError() }
        do { try await service.withSession(expectedCredentials: credentials, operation: operation) }
        catch {
            let hasNoCredentials = await service.refresh.current() == nil
            let sameInstallation = await service.refresh.isSameInstallation(credentials)
            guard !APIError.isCancellation(error), sameInstallation,
                  identityGeneration == generation, user?.id == accountID, stage == .signedIn else { throw CancellationError() }
            if APIError.status(error) == 401 || hasNoCredentials { await invalidateSession(message: APIError.display(error)) }
            else if APIError.status(error) == 403 { await foreground() }
            throw error
        }
        guard await service.refresh.isCurrent(credentials),
              identityGeneration == generation, user?.id == accountID, stage == .signedIn else { throw CancellationError() }
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        do {
            configuration = try await service.configuration()
            guard await service.refresh.current() != nil else { stage = .signIn; return }
            try await loadIdentity()
        } catch {
            guard !(error is CancellationError) else { return }
            self.error = APIError.display(error)
            if isUnauthorized(error) { await invalidateSession(message: APIError.display(error)) }
            stage = .signIn
        }
    }
    func signIn() async {
        guard !busy, (retryAfter ?? .distantPast) <= Date() else { return }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            error = String(localized: "Enter your email or username and password."); return
        }
        busy = true; error = nil
        defer { busy = false; password = "" }
        do {
            let challenge = try await service.challenge(appID: Brand.bundleID, development: NativeAttestor.development)
            let expires = Date().addingTimeInterval(TimeInterval(challenge.expires_in))
            let proof = try await attest(challenge.challenge)
            guard Date() < expires else { throw APIError(status: 0, code: "challenge_expired", detail: String(localized: "Your sign-in expired. Try again.")) }
            let result = try await service.signIn(appID: Brand.bundleID, development: NativeAttestor.development,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                challenge: challenge.challenge, attestationJSON: proof)
            switch result {
            case .DeviceTokenResponse(let tokens):
                try await accept(TokenPair(access: tokens.access, refresh: tokens.refresh))
            case .MFAChallengeResponse(let challenge):
                mfa = challenge
                mfaExpires = Date().addingTimeInterval(TimeInterval(challenge.expires_in))
                if challenge.enrollment_required { enrollment = try await service.enroll(challenge: challenge.challenge) }
                stage = .mfa
            }
        } catch { fail(error) }
    }
    func verify() async {
        guard !busy, let mfa, (retryAfter ?? .distantPast) <= Date() else { return }
        guard (mfaExpires ?? .distantPast) > Date() else {
            backToSignIn(); error = String(localized: "Your sign-in expired. Try again."); return
        }
        guard code.count >= 6 else { error = String(localized: "Enter your authenticator or recovery code."); return }
        busy = true; error = nil
        defer { busy = false; code = "" }
        do {
            let result = try await service.verify(challenge: mfa.challenge, code: code, enrolling: mfa.enrollment_required)
            let grantData = try result.device_grant.map { try JSONEncoder().encode($0) }
            let grant = grantData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let refresh = result.refresh, !refresh.isEmpty, !result.access.isEmpty,
                  result.surface != "verification_only", let grantID = grant?["id"] as? String, UUID(uuidString: grantID) != nil else {
                throw APIError(status: 0, code: "native_session_missing", detail: String(localized: "This server did not provide a device session. Contact your makerspace."))
            }
            recoveryCodes = result.recovery_codes ?? []
            try await accept(TokenPair(access: result.access, refresh: refresh))
            if !recoveryCodes.isEmpty { stage = .recoveryCodes }
        } catch { fail(error) }
    }
    func confirmRecoveryCodes() { recoveryCodes = []; stage = user?.must_change_password == true ? .passwordChange : .signedIn }
    func backToSignIn() {
        guard !busy else { return }
        mfa = nil; mfaExpires = nil; enrollment = nil; code = ""; error = nil; stage = .signIn
    }
    func select(_ id: Int) async {
        do {
            try await service.makerspace.select(id, activeMemberships: Set(memberships.map(\.id)))
            selectedID = id
            settings.set(id, forKey: selectionKey)
        } catch {
            try? await service.makerspace.select(nil, activeMemberships: Set(memberships.map(\.id)))
            selectedID = nil; fail(error)
        }
    }
    func foreground() async {
        guard stage == .signedIn, !busy, (retryAfter ?? .distantPast) <= Date() else { return }
        let generation = identityGeneration
        defer { if let notifications { Task { await notifications.refresh() } } }
        do { try await refreshedIdentity() } catch {
            guard generation == identityGeneration else { return }
            fail(error)
            let hasNoCredentials = await service.refresh.current() == nil
            if isUnauthorized(error) || hasNoCredentials { await invalidateSession(message: APIError.display(error)) }
        }
    }
    func invalidateSession(message: String) async {
        guard !endingSession else { return }
        endingSession = true; busy = true; defer { busy = false; endingSession = false }
        let cleanup = detachNotificationCleanup()
        clearLocalIdentity()
        await cleanup.state?.stop(authorizedDirectMembershipIDs: cleanup.ids)
        try? await service.refresh.install(nil)
        try? await service.makerspace.select(nil, activeMemberships: [])
        error = message
    }
    func signOut() async {
        guard !busy, !endingSession else { return }
        endingSession = true; busy = true; error = nil
        defer { busy = false; endingSession = false }
        let cleanup = detachNotificationCleanup()
        clearLocalIdentity()
        await cleanup.state?.stop(authorizedDirectMembershipIDs: cleanup.ids)
        var revocationFailed = false
        do { try await service.signOut() } catch { revocationFailed = true }
        do {
            try await service.refresh.install(nil)
            await clear()
            if revocationFailed { error = String(localized: "Signed out on this device. Server revocation could not be confirmed.") }
        } catch { await clear(); fail(error) }
    }
    func changePassword(current: String, new: String, confirmation: String) async {
        guard stage == .passwordChange, !busy, (retryAfter ?? .distantPast) <= Date(), let accountID = user?.id, let credentials = acceptedCredentials else { return }
        guard !current.isEmpty, !new.isEmpty, new == confirmation else {
            error = String(localized: "Enter your current password and matching new passwords."); return
        }
        let generation = identityGeneration
        busy = true; error = nil
        defer { busy = false }
        let repository = LiveAccountRepository(service: service, expectedCredentials: credentials, makerspaceID: nil, origin: origin,
            onUnauthorized: { [weak self] message in await self?.accountRefused(message, accountID: accountID, generation: generation) },
            onForbidden: { [weak self] in await self?.accountAuthorityChanged(accountID: accountID, generation: generation) })
        do {
            try await repository.updateTemporaryPassword(current: current, new: new)
            guard identityGeneration == generation, stage == .passwordChange, user?.id == accountID else { return }
            // The required temporary-password gate always returns to native authentication.
            // Release busy synchronously so signOut can immediately claim teardown ownership.
            busy = false; await signOut()
            if stage == .signIn, user == nil { error = String(localized: "Password updated. Sign in again.") }
        } catch {
            guard identityGeneration == generation else { return }
            fail(error)
        }
    }
    /// Global security works before joining a makerspace; membership records remain bootstrap-gated.
    func accountState(makerspaceID: Int?, selfService: Bool = false, exports: Bool = false) -> AccountState? {
        guard let accountID = user?.id, let credentials = acceptedCredentials, stage == .signedIn,
              makerspaceID == nil || memberships.contains(where: { $0.id == makerspaceID }) else { return nil }
        let generation = identityGeneration
        let name = memberships.first(where: { $0.id == makerspaceID })?.slug ?? ""
        let repository = LiveAccountRepository(service: service, expectedCredentials: credentials, makerspaceID: makerspaceID, origin: origin,
            onUnauthorized: { [weak self] message in await self?.accountRefused(message, accountID: accountID, generation: generation) },
            onForbidden: { [weak self] in await self?.accountAuthorityChanged(accountID: accountID, generation: generation) })
        return AccountState(repository: repository, makerspaceID: makerspaceID, makerspaceName: name,
            selfServiceEnabled: selfService, exportEnabled: exports,
            phoneCooldown: AccountAccessCooldown.scoped(serverScope + ".account.\(accountID).phone-link"),
            endSession: { [weak self] codes, message in
                guard let self, self.identityGeneration == generation, self.user?.id == accountID else { return }
                await self.securitySessionEnded(codes: codes, message: message)
            },
            membershipEnded: { [weak self] in guard let self, self.identityGeneration == generation, self.user?.id == accountID, let makerspaceID else { return }; await self.confirmedMembershipLeave(makerspaceID) },
            passwordChanged: { [weak self] in guard let self, self.identityGeneration == generation, self.user?.id == accountID else { return }; await self.foreground() },
            beforeLeave: { [weak self] in
                guard let self, self.identityGeneration == generation, let makerspaceID, self.user?.id == accountID else { throw CancellationError() }
                let ids = try await self.freshMembershipIDs()
                guard ids.contains(makerspaceID), self.user?.id == accountID else { throw CancellationError() }
                if let notifications = self.notifications {
                    guard await notifications.registration.removeMembership(makerspaceID, authorizedDirectMembershipIDs: ids) else {
                        throw APIError(status: notifications.registration.retryAfter > Date() ? 429 : 0,
                            code: "membership_notification_cleanup", detail: notifications.registration.error ?? String(localized: "Device notifications could not be updated. Try again before leaving."),
                            retryAfter: notifications.registration.retryAfter > Date() ? notifications.registration.retryAfter : nil)
                    }
                }
                guard self.user?.id == accountID, self.stage == .signedIn else { throw CancellationError() }
            }, leaveFailed: { [weak self] in
                guard let self, self.identityGeneration == generation, let makerspaceID, self.user?.id == accountID else { return }
                if let ids = try? await self.freshMembershipIDs(), ids.contains(makerspaceID), self.user?.id == accountID {
                    await self.notifications?.registration.resumeMembership(makerspaceID, authorizedDirectMembershipIDs: ids)
                }
            })
    }
    private func accountRefused(_ message: String, accountID: Int, generation: Int) async {
        guard identityGeneration == generation, user?.id == accountID else { return }
        await invalidateSession(message: message)
    }
    private func accountAuthorityChanged(accountID: Int, generation: Int) async {
        guard identityGeneration == generation, user?.id == accountID else { return }
        await foreground()
    }
    func securitySessionEnded(codes: [String], message: String?) async {
        await invalidateSession(message: message ?? String(localized: "Sign in again to continue."))
        guard user == nil, stage == .signIn, !endingSession else { return }
        recoveryCodes = codes; securityMessage = message ?? String(localized: "Your security settings changed. Sign in again.")
        stage = .securityCompletion
    }
    func finishSecurityCompletion() { recoveryCodes = []; securityMessage = nil; stage = .signIn }
    /// A confirmed server leave revokes local scope immediately, even when the following /me is offline.
    /// Ignore stale membership echoes until a fresh native sign-in establishes a new account session.
    func confirmedMembershipLeave(_ id: Int) async {
        guard stage == .signedIn, memberships.contains(where: { $0.id == id }) else { return }
        let accountID = user?.id
        locallyLeftMemberships.insert(id); clearPrivateHolders()
        identityGeneration += 1; identityFlight?.cancel(); identityFlight = nil; busy = false
        settings.removeObject(forKey: selectionKey)
        user?.makerspaces.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        let ids = Set(memberships.map(\.id))
        try? await service.makerspace.select(selectedID, activeMemberships: ids)
        guard user?.id == accountID, stage == .signedIn else { return }
        do { try await refreshedIdentity() }
        catch {
            guard user?.id == accountID, stage == .signedIn else { return }
            fail(error)
            if isUnauthorized(error) { await invalidateSession(message: APIError.display(error)) }
        }
    }
    private func accept(_ pair: TokenPair) async throws {
        guard !pair.access.isEmpty, !pair.refresh.isEmpty else {
            throw APIError(status: 0, code: "native_session_missing", detail: String(localized: "This server did not provide a device session. Contact your makerspace."))
        }
        try await service.refresh.install(pair)
        do { try await loadIdentity() } catch {
            await stopNotifications()
            try? await service.refresh.install(nil)
            throw error
        }
    }
    private func loadIdentity() async throws {
        let generation = identityGeneration
        let credentials = await service.refresh.snapshot()
        var identity = try await service.me()
        guard generation == identityGeneration, await service.refresh.isCurrent(credentials) else { throw CancellationError() }
        guard !identity.is_superuser else {
            await invalidateSession(message: "Use the web console")
            throw APIError(status: 403, code: "device_superadmin_not_supported", detail: String(localized: "Use the web console"))
        }
        identity.makerspaces.removeAll { locallyLeftMemberships.contains($0.id) }
        let direct = identity.makerspaces.filter { $0.source == .membership }
        let ids = Set(direct.map(\.id))
        let previous = user?.id == identity.id ? selectedID : nil
        let saved = previous ?? settings.object(forKey: "makerspace-selection.\(serverScope).\(identity.id)") as? Int
        let selection = saved.flatMap { ids.contains($0) ? $0 : nil } ?? (direct.count == 1 ? direct.first?.id : nil)
        if selectedID != selection || user?.id != identity.id { clearPrivateHolders() }
        try await service.makerspace.select(selection, activeMemberships: ids)
        guard generation == identityGeneration, await service.refresh.isCurrent(credentials) else { throw CancellationError() }
        if let pushAccountID, pushAccountID != identity.id { detachNotifications() }
        acceptedCredentials = credentials
        user = identity; selectedID = selection
        stage = identity.must_change_password ? .passwordChange : .signedIn
        if stage == .signedIn { configureNotifications(accountID: identity.id, credentials: credentials) }
    }
    /// Push registration, foreground refresh and notification taps share one current identity read.
    /// Publication and busy-state release happen inside the shared task before any waiter proceeds.
    private func refreshedIdentity() async throws {
        if let identityFlight { return try await identityFlight.value }
        guard !busy, !endingSession else { throw CancellationError() }
        let generation = identityGeneration; busy = true
        let task = Task {
            do {
                try await self.loadIdentity()
                guard self.identityGeneration == generation else { throw CancellationError() }
                self.identityFlight = nil; self.busy = false
            } catch {
                if self.identityGeneration == generation { self.identityFlight = nil; self.busy = false }
                throw error
            }
        }
        identityFlight = task
        try await task.value
    }
    /// Routing and registration require a successful current /me, never the last cached identity.
    func freshMembershipIDs() async throws -> Set<Int> {
        if let deadline = retryAfter, deadline > Date() { throw APIError(status: 429, code: "identity_throttled", detail: error ?? String(localized: "Too many requests. Try again later."), retryAfter: deadline) }
        guard stage == .signedIn, !endingSession, let accountID = user?.id else { throw CancellationError() }
        let generation = identityGeneration
        do {
            try await refreshedIdentity()
            guard generation == identityGeneration, stage == .signedIn, user?.id == accountID else { throw CancellationError() }
            return Set(memberships.map(\.id))
        } catch {
            guard generation == identityGeneration, user?.id == accountID else { throw CancellationError() }
            fail(error)
            let noCredentials = await service.refresh.current() == nil
            if isUnauthorized(error) || noCredentials { await invalidateSession(message: APIError.display(error)) }
            throw error
        }
    }
    func queueForegroundHint(_ hint: NotificationHint) {
        guard stage == .signedIn, let accountID = user?.id, selectedID == hint.makerspaceID else { return }
        pendingForegroundHint = (accountID, hint.makerspaceID); foregroundHintRevision += 1
    }
    func processForegroundHint() async {
        guard !busy, let pending = pendingForegroundHint else { return }
        pendingForegroundHint = nil
        guard stage == .signedIn, user?.id == pending.accountID, selectedID == pending.makerspaceID else { return }
        do {
            let ids = try await freshMembershipIDs()
            guard stage == .signedIn, user?.id == pending.accountID, selectedID == pending.makerspaceID,
                  ids.contains(pending.makerspaceID) else { return }
            inboxRefreshMakerspaceID = pending.makerspaceID; inboxRefreshRevision += 1
        } catch { /* Existing identity error/cooldown is visible. A hint cannot fall back to cached authority. */ }
    }
    func selectForLink(_ id: Int) async throws {
        guard stage == .signedIn, memberships.contains(where: { $0.id == id }) else { throw CancellationError() }
        if selectedID != id { clearPrivateHolders() }
        try await service.makerspace.select(id, activeMemberships: Set(memberships.map(\.id)))
        selectedID = id; settings.set(id, forKey: selectionKey)
    }
    private func configureNotifications(accountID: Int, credentials: CredentialSnapshot) {
        guard pushAccountID == nil, notifications == nil else { return }
        pushAccountID = accountID
        let failureHandlers = repositoryFailureHandlers()
        let registration = PushRegistrationState(repository: LivePushRegistrationRepository(service: service, expectedCredentials: credentials),
            storage: PushRegistrationVault(origin: origin, accountID: accountID), configured: Brand.pushConfigured,
            onUnauthorized: failureHandlers.unauthorized, onForbidden: failureHandlers.forbidden)
        let notificationState = NotificationSettingsState(registration: registration, environment: Brand.pushEnvironment,
            memberships: { [weak self] in guard let self, self.user?.id == accountID else { throw CancellationError() }; return try await self.freshMembershipIDs() })
        notifications = notificationState
        Self.notificationOwner = notificationOwnerID
        NativeNotifications.shared.onTokenChanged = { [weak notificationState] token in Task { await notificationState?.tokenChanged(token) } }
        NativeNotifications.shared.onForegroundHint = { [weak self] hint in self?.queueForegroundHint(hint) }
        Task { await notificationState.prepare() }
    }
    private func detachNotifications() {
        notifications?.detach(); notifications = nil; pushAccountID = nil; pendingForegroundHint = nil; inboxRefreshMakerspaceID = nil
        if Self.notificationOwner == notificationOwnerID { Self.notificationOwner = nil; NativeNotifications.shared.reset() }
    }
    private func detachNotificationCleanup() -> (state: NotificationSettingsState?, ids: Set<Int>) {
        let old = notifications; let ids = Set(memberships.map(\.id))
        notifications = nil; pushAccountID = nil; pendingForegroundHint = nil; inboxRefreshMakerspaceID = nil
        if Self.notificationOwner == notificationOwnerID {
            Self.notificationOwner = nil
            // Detach synchronously before a server cleanup can suspend. A later owner keeps its callbacks.
            NativeNotifications.shared.reset()
        }
        return (old, ids)
    }
    func stopNotifications() async {
        let cleanup = detachNotificationCleanup()
        await cleanup.state?.stop(authorizedDirectMembershipIDs: cleanup.ids)
    }
    /// Capture failure ownership on MainActor before a repository can hop executors.
    /// The callback rechecks this identity on MainActor, without an intervening await.
    func repositoryFailureHandlers() -> (unauthorized: @Sendable (String) async -> Void, forbidden: @Sendable () async -> Void) {
        let generation = identityGeneration; let accountID = user?.id
        return (
            { [weak self] message in await self?.repositoryRefused(message, accountID: accountID, generation: generation) },
            { [weak self] in await self?.repositoryAuthorityChanged(accountID: accountID, generation: generation) }
        )
    }
    private func repositoryRefused(_ message: String, accountID: Int?, generation: Int) async {
        guard let accountID, identityGeneration == generation, user?.id == accountID, acceptedCredentials != nil else { return }
        await invalidateSession(message: message)
    }
    private func repositoryAuthorityChanged(accountID: Int?, generation: Int) async {
        guard let accountID, identityGeneration == generation, user?.id == accountID, acceptedCredentials != nil else { return }
        await foreground()
    }
    func registerPrivateHolder(_ owner: UUID, clear: @escaping () -> Void) { privateHolders[owner] = clear }
    func unregisterPrivateHolder(_ owner: UUID) { privateHolders.removeValue(forKey: owner) }
    private func clearPrivateHolders() {
        let holders = privateHolders; privateHolders = [:]
        for clear in holders.values { clear() }
    }
    private func clearLocalIdentity() {
        identityGeneration += 1; identityFlight?.cancel(); identityFlight = nil; clearPrivateHolders()
        settings.removeObject(forKey: selectionKey)
        locallyLeftMemberships = []; securityMessage = nil; acceptedCredentials = nil
        user = nil; selectedID = nil; mfa = nil; mfaExpires = nil; enrollment = nil; recoveryCodes = []
        username = ""; password = ""; code = ""; stage = .signIn
    }
    private func clear() async {
        let cleanup = detachNotificationCleanup()
        clearLocalIdentity()
        await cleanup.state?.stop(authorizedDirectMembershipIDs: cleanup.ids)
        try? await service.makerspace.select(nil, activeMemberships: [])
    }
    private func fail(_ failure: Error) {
        guard !(failure is CancellationError) else { return }
        error = APIError.display(failure); retryAfter = APIError.retryDeadline(failure)
    }
    private func isUnauthorized(_ failure: Error) -> Bool {
        APIError.status(failure) == 401
    }
}
