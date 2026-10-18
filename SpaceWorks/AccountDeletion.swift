import Foundation
import Observation
import SpaceWorksAPI

/// Whole-account deletion across every makerspace on this server. Leaving one makerspace is separate.
protocol AccountDeletionRepository: Sendable {
    func preview() async throws -> Components.Schemas.AccountDeletionPreview
    func status() async throws -> Components.Schemas.ReauthenticationStatus
    func reauthenticate(password: String, code: String?) async throws -> Components.Schemas.ReauthenticationResult
    func startPhone() async throws -> Components.Schemas.ReauthenticationPhoneStarted
    func confirmPhone(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult
    func startSocial(provider: String) async throws -> Components.Schemas.ReauthenticationSocialStarted
    func completeSocial(state: String, nonce: String, idToken: String) async throws -> Components.Schemas.ReauthenticationResult
    func factor(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult
    func delete() async throws -> Components.Schemas.AccountDeletionResult
}

struct LiveAccountDeletionRepository: AccountDeletionRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }

    /// Identity proofs answer 401 for a wrong credential. Only a failed identity probe ends the session.
    private func checked<T: Sendable>(proof: Bool = false, _ work: @Sendable () async throws -> T) async throws -> T {
        guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        do { return try await service.withSession(expectedCredentials: expectedCredentials, operation: work) }
        catch {
            if Task.isCancelled || APIError.isCancellation(error) { throw error }
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            let empty = await service.refresh.current() == nil
            if proof, APIError.status(error) == 401, !empty {
                do { _ = try await service.withSession(expectedCredentials: expectedCredentials) { try await service.me() } }
                catch {
                    if Task.isCancelled || APIError.isCancellation(error) { throw error }
                    let signedOut = await service.refresh.current() == nil
                    if APIError.status(error) == 401 || signedOut { await onUnauthorized(APIError.display(error)) }
                    throw error
                }
                throw APIError(status: 0, code: "identity_verification_failed", detail: APIError.display(error), retryAfter: APIError.retryDeadline(error))
            }
            if APIError.status(error) == 401 || empty { await onUnauthorized(APIError.display(error)) }
            throw error
        }
    }
    func preview() async throws -> Components.Schemas.AccountDeletionPreview { try await checked { try await service.accountDeletionPreview() } }
    func status() async throws -> Components.Schemas.ReauthenticationStatus { try await checked { try await service.reauthenticationStatus() } }
    func reauthenticate(password: String, code: String?) async throws -> Components.Schemas.ReauthenticationResult {
        try await checked(proof: true) { try await service.reauthenticate(password: password, code: code) }
    }
    func startPhone() async throws -> Components.Schemas.ReauthenticationPhoneStarted { try await checked { try await service.reauthenticationPhoneStart() } }
    func confirmPhone(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await checked(proof: true) { try await service.reauthenticationPhoneConfirm(token: token, code: code) }
    }
    func startSocial(provider: String) async throws -> Components.Schemas.ReauthenticationSocialStarted {
        try await checked { try await service.reauthenticationSocialStart(provider: provider) }
    }
    func completeSocial(state: String, nonce: String, idToken: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await checked(proof: true) { try await service.reauthenticationSocialComplete(state: state, nonce: nonce, idToken: idToken) }
    }
    func factor(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await checked(proof: true) { try await service.reauthenticationFactor(token: token, code: code) }
    }
    func delete() async throws -> Components.Schemas.AccountDeletionResult { try await checked { try await service.deleteAccount() } }
}

extension AccountState {
    func withDeletion(origin: ServerOrigin, memberships: Set<Int>, make: @escaping @MainActor () -> AccountDeletionState?) -> AccountState {
        deletionOrigin = origin; deletionMemberships = memberships; makeDeletion = make
        return self
    }
}

@MainActor @Observable
final class AccountDeletionState {
    enum Stage: Equatable { case overview, blockers, verify, factor, confirm, deleted }
    enum Method: Hashable, Identifiable {
        case password, phone, social(String)
        var id: String { switch self { case .password: return "password"; case .phone: return "phone"; case .social(let key): return key } }
    }
    private(set) var stage = Stage.overview
    private(set) var preview: Components.Schemas.AccountDeletionPreview?
    private(set) var status: Components.Schemas.ReauthenticationStatus?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var retryAfter = Date.distantPast
    private(set) var phoneToken: String?
    private(set) var factorKind: Components.Schemas.FactorRequiredEnum?
    private(set) var codeRequired = false
    var method = Method.password
    var password = ""
    var code = ""
    var confirmation = ""
    private var factorToken: String?
    private var proofExpires: Date?
    private var active = true
    private let repository: any AccountDeletionRepository
    private let socialCredential: @MainActor (String, String) async throws -> ProviderCredential
    private let onDeleted: @MainActor (Components.Schemas.AccountDeletionResult, Bool) async -> Void
    private let now: () -> Date

    init(repository: any AccountDeletionRepository,
         socialCredential: @escaping @MainActor (String, String) async throws -> ProviderCredential = { _, _ in throw NativeIdentity.unavailable },
         onDeleted: @escaping @MainActor (Components.Schemas.AccountDeletionResult, Bool) async -> Void, now: @escaping () -> Date = Date.init) {
        self.repository = repository; self.socialCredential = socialCredential; self.onDeleted = onDeleted; self.now = now
    }

    var blockers: [Components.Schemas.AccountDeletionBlocker] { preview?.blockers ?? [] }
    /// Server-listed methods this app can complete natively. TOTP is the password's second factor.
    var methods: [Method] {
        (preview?.reauth.methods ?? []).compactMap { (key: String) -> Method? in
            switch key {
            case "password": return .password
            case "phone": return .phone
            case "google", "apple": return .social(key)
            default: return NativeOIDCClient.slug(fromKey: key) != nil ? .social(key) : nil
            }
        }
    }
    var authenticatorRequired: Bool { codeRequired || status?.mfa_enabled == true }
    var proofValid: Bool { (proofExpires ?? .distantPast) > now() }
    var canDelete: Bool { active && !busy && stage == .confirm && confirmation == "DELETE" && proofValid }

    func load() async {
        guard active, !busy, now() >= retryAfter else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await repository.preview()
            let identity = try await repository.status()
            guard active else { return }
            preview = value; status = identity; notice = nil
            if let first = methods.first, !methods.contains(method) { method = first }
            if !value.blockers.isEmpty { stage = .blockers }
            else if identity.verified, proofValid { stage = .confirm }
            else { proofExpires = nil; stage = .verify }
        } catch { fail(error) }
    }

    func verifyPassword() async {
        guard active, !busy, stage == .verify, method == .password else { return }
        guard !password.isEmpty else { error = String(localized: "Enter your current password."); return }
        let digits = code.filter { $0.isASCII && $0.isNumber }
        if authenticatorRequired, digits.count != 6 { error = String(localized: "Enter the six-digit code from your authenticator app."); return }
        await prove { try await self.repository.reauthenticate(password: self.password, code: self.authenticatorRequired ? digits : nil) }
    }

    func sendPhoneCode() async {
        guard active, !busy, stage == .verify, method == .phone, now() >= retryAfter else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let started = try await repository.startPhone()
            guard active else { return }
            phoneToken = started.token; code = ""
            notice = started.sent ? String(localized: "We sent a verification code to your phone.") : nil
        } catch { fail(error) }
    }

    func verifyPhone() async {
        guard active, !busy, stage == .verify, method == .phone, let token = phoneToken else { return }
        let digits = code.filter { $0.isASCII && $0.isNumber }
        guard digits.count == 6 else { error = String(localized: "Enter the six-digit code."); return }
        await prove { try await self.repository.confirmPhone(token: token, code: digits) }
    }

    func verifySocial(_ provider: String) async {
        guard active, !busy, stage == .verify, now() >= retryAfter else { return }
        busy = true; error = nil
        var started: Components.Schemas.ReauthenticationSocialStarted?
        do {
            started = try await repository.startSocial(provider: provider)
        } catch { busy = false; fail(error); return }
        guard let started, active else { busy = false; return }
        let expires = now().addingTimeInterval(TimeInterval(started.expires_in))
        do {
            let credential = try await socialCredential(provider, started.nonce)
            guard now() < expires else { throw APIError(status: 0, code: "challenge_expired", detail: String(localized: "Verification expired. Try again.")) }
            busy = false
            await prove { try await self.repository.completeSocial(state: started.state, nonce: started.nonce, idToken: credential.idToken) }
        } catch { busy = false; fail(error) }
    }

    func verifyFactor() async {
        guard active, !busy, stage == .factor, let token = factorToken else { return }
        let digits = code.filter { $0.isASCII && $0.isNumber }
        guard digits.count == 6 else { error = String(localized: "Enter the six-digit code."); return }
        await prove { try await self.repository.factor(token: token, code: digits) }
    }

    func delete() async {
        guard active, !busy, stage == .confirm else { return }
        guard proofValid else { requireProof(); return }
        guard confirmation == "DELETE" else { error = String(localized: "Type DELETE to confirm."); return }
        busy = true; error = nil
        do {
            let result = try await repository.delete()
            guard active else { busy = false; return }
            let restorable = preview?.restorable == true
            clearSecrets(); proofExpires = nil; stage = .deleted; busy = false
            await onDeleted(result, restorable)
        } catch {
            busy = false
            guard active, !APIError.isCancellation(error) else { return }
            let status = APIError.status(error) ?? 0, code = APIError.code(error) ?? ""
            if status == 409 || (status == 503 && code == "deletion_retry") {
                // The server rechecked participation; refresh the authoritative list before continuing.
                confirmation = ""
                await load()
                notice = String(localized: "Something changed. Review the updated list before continuing.")
            } else if status == 403 && code == "recent_reauth_required" { requireProof() }
            else { fail(error) }
        }
    }

    func backToVerification() { guard active, !busy else { return }; requireProof(); error = nil }
    func invalidate() { active = false; clearSecrets(); preview = nil; status = nil; proofExpires = nil; phoneToken = nil; factorToken = nil }

    private func prove(_ work: @escaping @MainActor () async throws -> Components.Schemas.ReauthenticationResult) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await work()
            guard active else { return }
            code = ""
            if result.verified {
                password = ""; factorToken = nil; factorKind = nil; codeRequired = false; notice = nil
                proofExpires = now().addingTimeInterval(TimeInterval(max(0, result.expires_in)))
                confirmation = ""; stage = .confirm
            } else if let token = result.factor_token, let kind = result.factor_required {
                password = ""; factorToken = token; factorKind = kind; stage = .factor
            } else if result.mfa_required == true {
                codeRequired = true; error = String(localized: "Enter the six-digit code from your authenticator app.")
            } else {
                error = String(localized: "Verify your identity to continue.")
            }
        } catch { fail(error) }
    }
    private func requireProof() {
        proofExpires = nil; confirmation = ""; factorToken = nil; factorKind = nil; code = ""
        stage = blockers.isEmpty ? .verify : .blockers
        error = String(localized: "Verify your identity again before deleting.")
    }
    private func clearSecrets() { password = ""; code = ""; confirmation = "" }
    private func fail(_ failure: Error) {
        guard active, !APIError.isCancellation(failure) else { return }
        error = APIError.display(failure)
        if let deadline = APIError.retryDeadline(failure) { retryAfter = deadline }
    }

    /// In-app fixes for blockers in a current membership. Organization and other fixes stay on the web.
    static func destination(for blocker: Components.Schemas.AccountDeletionBlocker) -> MobileLink.Destination? {
        switch blocker.code {
        case "unpaid_charges", "refund_in_progress", "deposit_held": return .payments
        case "active_loans", "open_requests": return .activity
        case "upcoming_bookings": return .bookings
        case "upcoming_registrations": return .events
        default: return nil
        }
    }
    /// Server-provided web fixes open only on the connected deployment's own HTTPS origin.
    static func trustedWebFix(_ value: String?, origin: ServerOrigin) -> URL? {
        guard let value, let url = URL(string: value), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              parts.host?.lowercased() == origin.url.host?.lowercased(), (parts.port ?? 443) == (origin.url.port ?? 443) else { return nil }
        return url
    }
}
