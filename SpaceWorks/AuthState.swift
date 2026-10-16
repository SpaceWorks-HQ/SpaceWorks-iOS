import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class AuthState {
    enum Stage: Equatable { case restoring, signIn, mfa, recoveryCodes, signedIn }
    private(set) var stage: Stage = .restoring
    var username = ""
    var password = ""
    var code = ""
    private(set) var busy = false
    private(set) var error: String?
    private(set) var retryAfter: Date?
    private(set) var user: Components.Schemas.AuthUserPayload?
    private(set) var mfa: Components.Schemas.MFAChallengeResponse?
    private(set) var enrollment: Components.Schemas.MFAEnrollment?
    private(set) var recoveryCodes: [String] = []
    private(set) var selectedID: Int?
    private(set) var configuration: Components.Schemas.PublicConfig?
    let service: SpaceWorksService
    private let attest: @Sendable (String) async throws -> Data
    private let settings: UserDefaults
    private let storage: any TokenStorage
    private var restored = false
    private var mfaExpires: Date?

    init(origin: ServerOrigin, session: URLSession = DeploymentSession.make(), settings: UserDefaults = .standard,
         storage: (any TokenStorage)? = nil,
         attest: @escaping @Sendable (String) async throws -> Data = { try await NativeAttestor.attest($0) }) {
        let storage = storage ?? TokenVault(origin: origin)
        self.storage = storage
        self.attest = attest
        self.settings = settings
        var pair: TokenPair?
        var storageError: String?
        do { pair = try storage.load() } catch { storageError = APIError.display(error) }
        service = SpaceWorksService(origin: origin, session: session, initialTokens: pair, persist: { try storage.store($0) })
        error = storageError
    }
    var memberships: [Components.Schemas.AuthMembership] {
        // Organization-derived authority is excluded by the mobile scope. /me supplies active memberships.
        user?.makerspaces.filter { $0.source == .membership } ?? []
    }
    var selectedMembership: Components.Schemas.AuthMembership? { memberships.first { $0.id == selectedID } }
    var displayName: String { user?.display_name.isEmpty == false ? user!.display_name : user?.username ?? "" }
    var passwordEnabled: Bool {
        guard let configuration, let data = try? JSONEncoder().encode(configuration),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object["password_login"] as? [String: Any] else { return true }
        // PublicConfig's extensible object; same documented switch consumed by MemberAuthPanel.
        return login["enabled"] as? Bool != false
    }
    // Fail closed until the schema supplies native_staff authority (backend 1a).
    var staffToolsAvailable: Bool { false }

    func restore() async {
        guard !restored else { return }
        restored = true
        do {
            configuration = try await service.configuration()
            guard await service.refresh.current() != nil else { stage = .signIn; return }
            try await loadIdentity()
        } catch {
            error = APIError.display(error)
            if isUnauthorized(error) { try? await service.refresh.install(nil) }
            stage = .signIn
        }
    }
    func signIn() async {
        guard !busy, (retryAfter ?? .distantPast) <= Date() else { return }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            error = "Enter your email or username and password."; return
        }
        busy = true; error = nil
        defer { busy = false; password = "" }
        do {
            let challenge = try await service.challenge(appID: Brand.bundleID, development: NativeAttestor.development)
            let expires = Date().addingTimeInterval(TimeInterval(challenge.expires_in))
            let proof = try await attest(challenge.challenge)
            guard Date() < expires else { throw APIError(status: 0, code: "challenge_expired", detail: "Your sign-in expired. Try again.") }
            let result = try await service.signIn(appID: Brand.bundleID, development: NativeAttestor.development,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                challenge: challenge.challenge, attestationJSON: proof)
            switch result {
            case .case1(let tokens):
                try await accept(TokenPair(access: tokens.access, refresh: tokens.refresh))
            case .case2(let challenge):
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
            backToSignIn(); error = "Your sign-in expired. Try again."; return
        }
        guard code.count >= 6 else { error = "Enter your authenticator or recovery code."; return }
        busy = true; error = nil
        defer { busy = false; code = "" }
        do {
            let result = try await service.verify(challenge: mfa.challenge, code: code, enrolling: mfa.enrollment_required)
            let grantData = try result.device_grant.map { try JSONEncoder().encode($0) }
            let grant = grantData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let refresh = result.refresh, !refresh.isEmpty, !result.access.isEmpty,
                  result.surface != "verification_only", let grantID = grant?["id"] as? String, UUID(uuidString: grantID) != nil else {
                throw APIError(status: 0, code: "native_session_missing", detail: "This server did not provide a device session. Contact your makerspace.")
            }
            recoveryCodes = result.recovery_codes ?? []
            try await accept(TokenPair(access: result.access, refresh: refresh))
            if !recoveryCodes.isEmpty { stage = .recoveryCodes }
        } catch { fail(error) }
    }
    func confirmRecoveryCodes() { recoveryCodes = []; stage = .signedIn }
    func backToSignIn() {
        guard !busy else { return }
        mfa = nil; mfaExpires = nil; enrollment = nil; code = ""; error = nil; stage = .signIn
    }
    func select(_ id: Int) async {
        do {
            try await service.makerspace.select(id, activeMemberships: Set(memberships.map(\.id)))
            selectedID = id
            settings.set(id, forKey: "makerspace-selection")
        } catch { fail(error) }
    }
    func foreground() async {
        guard stage == .signedIn, !busy else { return }
        busy = true
        defer { busy = false }
        do { try await loadIdentity() } catch {
            fail(error)
            if isUnauthorized(error) { try? await service.refresh.install(nil); await clear() }
        }
    }
    func signOut() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        var revocationFailed = false
        do { try await service.signOut() } catch { revocationFailed = true }
        do {
            try await service.refresh.install(nil)
            await clear()
            if revocationFailed { error = "Signed out on this device. Server revocation could not be confirmed." }
        } catch { await clear(); fail(error) }
    }
    private func accept(_ pair: TokenPair) async throws {
        guard !pair.access.isEmpty, !pair.refresh.isEmpty else {
            throw APIError(status: 0, code: "native_session_missing", detail: "This server did not provide a device session. Contact your makerspace.")
        }
        try await service.refresh.install(pair)
        do { try await loadIdentity() } catch {
            try? await service.refresh.install(nil)
            throw error
        }
    }
    private func loadIdentity() async throws {
        let identity = try await service.me()
        guard !identity.is_superuser else {
            try? await service.refresh.install(nil)
            throw APIError(status: 403, code: "device_superadmin_not_supported", detail: "Use the web console")
        }
        user = identity
        let ids = Set(memberships.map(\.id))
        let saved = selectedID ?? settings.object(forKey: "makerspace-selection") as? Int
        let selection = saved.flatMap { ids.contains($0) ? $0 : nil } ?? (memberships.count == 1 ? memberships.first?.id : nil)
        try await service.makerspace.select(selection, activeMemberships: ids)
        selectedID = selection
        stage = .signedIn
    }
    private func clear() async {
        try? await service.makerspace.select(nil, activeMemberships: [])
        user = nil; selectedID = nil; mfa = nil; enrollment = nil; recoveryCodes = []
        password = ""; code = ""; settings.removeObject(forKey: "makerspace-selection"); stage = .signIn
    }
    private func fail(_ failure: Error) {
        guard !(failure is CancellationError) else { return }
        error = APIError.display(failure); retryAfter = APIError.retryDeadline(failure)
    }
    private func isUnauthorized(_ failure: Error) -> Bool {
        APIError.status(failure) == 401
    }
}
