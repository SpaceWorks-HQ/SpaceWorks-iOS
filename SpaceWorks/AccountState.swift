import Foundation
import Observation
import SpaceWorksAPI

/// Global security belongs to the account; makerspace records require a real enabled scope.
/// Secrets remain in memory only.
@MainActor @Observable
final class AccountState {
    enum Load: Equatable { case idle, loading, ready, failed(String) }
    let repository: any AccountRepository
    let makerspaceID: Int?
    private(set) var selfServiceEnabled: Bool
    private(set) var exportEnabled: Bool
    let makerspaceName: String
    let currentDeviceGrantID: String?
    /// Whole-account deletion is global; the authenticated owner supplies it and in-app blocker fixes.
    @ObservationIgnored var makeDeletion: (@MainActor () -> AccountDeletionState?)?
    @ObservationIgnored var deletionOrigin: ServerOrigin?
    @ObservationIgnored var deletionMemberships: Set<Int> = []
    @ObservationIgnored var openDeletionFix: (@MainActor (MobileLink) -> Void)?
    private let beginSecurityEnrollment: (Components.Schemas.MFAChallengeResponse) async -> Void
    private let endSession: ([String], String?) async -> Void
    private let membershipEnded: () async -> Void
    private let passwordChanged: () async -> Void
    private let beforeLeave: () async throws -> Void
    private let leaveFailed: () async -> Void
    private let phoneCooldown: AccountAccessCooldown
    private let now: () -> Date
    private let cooldownSleep: @Sendable (UInt64) async throws -> Void
    private var active = true
    private var sessionGeneration = 0
    private var grantGeneration = 0
    private var securityGeneration = 0
    private var membershipGeneration = 0
    private var providerGeneration = 0
    private var exportGeneration = 0
    private var downloadGeneration = 0
    private(set) var sessions: [Components.Schemas.AccountSession] = []
    private(set) var grants: [Components.Schemas.DeviceGrant] = []
    private(set) var exports: [Components.Schemas.SubjectExport] = []
    private(set) var membership: Components.Schemas.MembershipAccount?
    private(set) var mfa: Components.Schemas.MFAStatus?
    private(set) var providers: [Components.Schemas.SocialIdentity] = []
    private(set) var phoneStatus: Components.Schemas.PhoneStatus?
    private(set) var sessionsLoad = Load.idle
    private(set) var grantsLoad = Load.idle
    private(set) var exportsLoad = Load.idle
    private(set) var membershipLoad = Load.idle
    private(set) var securityLoad = Load.idle
    private(set) var providersLoad = Load.idle
    private(set) var sessionsHaveMore = false
    private(set) var exportsHaveMore = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var retryAfter = Date.distantPast
    var resendAfter: Date { phoneCooldown.resendAfter }
    private(set) var pendingPhone: String?
    var password = ""
    var phone = ""
    var phoneCountry = "+91"
    var code = ""
    var membershipReason = ""
    var archive: NativeDocumentFile?
    private(set) var downloading = false
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    init(repository: any AccountRepository, makerspaceID: Int?, makerspaceName: String,
         selfServiceEnabled: Bool = false, exportEnabled: Bool = false,
         currentDeviceGrantID: String? = nil,
         phoneCooldown: AccountAccessCooldown? = nil,
         now: @escaping () -> Date = Date.init,
         cooldownSleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         beginSecurityEnrollment: @escaping (Components.Schemas.MFAChallengeResponse) async -> Void = { _ in },
         endSession: @escaping ([String], String?) async -> Void = { _, _ in },
         membershipEnded: @escaping () async -> Void = {}, passwordChanged: @escaping () async -> Void = {},
         beforeLeave: @escaping () async throws -> Void = {}, leaveFailed: @escaping () async -> Void = {}) {
        self.repository = repository; self.makerspaceID = makerspaceID.flatMap { $0 > 0 ? $0 : nil }; self.makerspaceName = makerspaceName
        self.selfServiceEnabled = selfServiceEnabled; self.exportEnabled = exportEnabled
        self.currentDeviceGrantID = currentDeviceGrantID; self.beginSecurityEnrollment = beginSecurityEnrollment
        self.phoneCooldown = phoneCooldown ?? AccountAccessCooldown()
        self.now = now; self.cooldownSleep = cooldownSleep
        self.endSession = endSession; self.membershipEnded = membershipEnded; self.passwordChanged = passwordChanged
        self.beforeLeave = beforeLeave; self.leaveFailed = leaveFailed
    }
    var isDemo: Bool { repository.isDemo }
    var isActive: Bool { active }
    var canRequest: Bool { active && !busy && !downloading && now() >= retryAfter }
    var memberSelfServiceAvailable: Bool { makerspaceID != nil && selfServiceEnabled }
    var dataExportAvailable: Bool { makerspaceID != nil && exportEnabled }
    func updateCapabilities(selfService: Bool, exports: Bool) {
        if selfServiceEnabled && !selfService {
            sessionGeneration += 1; membershipGeneration += 1
            sessions = []; membership = nil; membershipReason = ""; sessionsHaveMore = false
            sessionsLoad = .idle; membershipLoad = .idle
        }
        if exportEnabled && !exports {
            exportGeneration += 1; downloadGeneration += 1
            self.exports = []; exportsHaveMore = false; archive = nil; downloading = false; exportsLoad = .idle
        }
        selfServiceEnabled = selfService; exportEnabled = exports
    }
    var canStartMFA: Bool { canRequest && isDemo && mfa?.available == true && mfa?.enabled == false }
    var canDisableMFA: Bool { canRequest && mfa?.enabled == true && mfa?.required == false }
    var canRegenerateRecovery: Bool { canRequest && mfa?.enabled == true && mfa?.available == true }
    #if DEBUG
    func previewProviderLink(_ provider: String, outcome: DemoAccountLinkOutcome) async {
        guard isDemo, canRequest, let demo = repository as? any DemoAccountLinking else { return }
        busy = true; error = nil; notice = nil
        do {
            _ = try await demo.linkProvider(provider, outcome: outcome); guard active else { return }
            busy = false; await loadProviders(); notice = String(localized: "Sample sign-in method connected.")
        } catch {
            guard active else { return }; busy = false
            if error is CancellationError { notice = String(localized: "Demo linking cancelled.") }
            else { fail(error) }
        }
    }
    #endif
    func invalidate() {
        active = false; cooldownTask?.cancel(); cooldownTask = nil; clearPrivateData()
    }
    private func clearPrivateData(preservingBusy: Bool = false) {
        sessionGeneration += 1; grantGeneration += 1; securityGeneration += 1; membershipGeneration += 1; providerGeneration += 1; exportGeneration += 1; downloadGeneration += 1
        sessions = []; grants = []; exports = []; membership = nil; mfa = nil; providers = []; phoneStatus = nil
        password = ""; phone = ""; code = ""; pendingPhone = nil; membershipReason = ""; archive = nil
        sessionsLoad = .idle; grantsLoad = .idle; membershipLoad = .idle; securityLoad = .idle; providersLoad = .idle; exportsLoad = .idle
        sessionsHaveMore = false; exportsHaveMore = false
        if !preservingBusy { busy = false }; downloading = false; error = nil; notice = nil
    }
    func loadSessions() async {
        guard memberSelfServiceAvailable, canRequest else { return }; sessionGeneration += 1; let generation = sessionGeneration
        sessionsLoad = .loading
        do {
            let result = try await repository.sessions(page: 1); guard active, generation == sessionGeneration else { return }
            sessions = result.results; sessionsHaveMore = result.next != nil; sessionsLoad = .ready
        } catch { guard active, generation == sessionGeneration else { return }; refuse(error); sessionsLoad = .failed(APIError.display(error)) }
    }
    func loadGrants() async {
        guard canRequest else { return }; grantGeneration += 1; let generation = grantGeneration; grantsLoad = .loading
        do { let result = try await repository.grants(); guard active, generation == grantGeneration else { return }; grants = result; grantsLoad = .ready }
        catch { guard active, generation == grantGeneration else { return }; refuse(error); grantsLoad = .failed(APIError.display(error)) }
    }
    func loadMembership() async {
        guard memberSelfServiceAvailable, canRequest else { return }; membershipGeneration += 1; let generation = membershipGeneration; membershipLoad = .loading
        do { let result = try await repository.membership(); guard active, generation == membershipGeneration else { return }; membership = result; membershipLoad = .ready }
        catch { guard active, generation == membershipGeneration else { return }; refuse(error); membershipLoad = .failed(APIError.display(error)) }
    }
    func loadSecurity() async {
        guard canRequest, securityLoad != .loading else { return }; securityGeneration += 1; let generation = securityGeneration; securityLoad = .loading
        do { let result = try await repository.mfa(); guard active, generation == securityGeneration else { return }; mfa = result; securityLoad = .ready }
        catch { guard active, generation == securityGeneration else { return }; refuse(error); securityLoad = .failed(APIError.display(error)) }
    }
    func loadProviders() async {
        guard canRequest else { return }; providerGeneration += 1; let generation = providerGeneration; providersLoad = .loading
        do { let result = try await repository.providers(); guard active, generation == providerGeneration else { return }; providers = result; providersLoad = .ready }
        catch { guard active, generation == providerGeneration else { return }; refuse(error); providersLoad = .failed(APIError.display(error)) }
    }
    func loadExports() async {
        guard dataExportAvailable, canRequest else { return }; exportGeneration += 1; let generation = exportGeneration
        exportsLoad = .loading
        do {
            let result = try await repository.exports(page: 1); guard active, generation == exportGeneration else { return }
            exports = result.results; exportsHaveMore = result.next != nil; exportsLoad = .ready
        } catch { guard active, generation == exportGeneration else { return }; refuse(error); exportsLoad = .failed(APIError.display(error)) }
    }
    func revokeSession(_ row: Components.Schemas.AccountSession) async {
        guard memberSelfServiceAvailable, canRequest, sessions.contains(where: { $0.id == row.id }) else { return }
        sessionGeneration += 1; let generation = sessionGeneration; sessionsLoad = .ready
        busy = true; error = nil; notice = nil; defer { if active { busy = false } }
        do {
            try await repository.revokeSession(id: row.id); guard active else { return }
            if row.current { invalidate(); await endSession([], "This session was signed out."); return }
            guard generation == sessionGeneration, memberSelfServiceAvailable else { return }
            sessions.removeAll { $0.id == row.id }; busy = false; notice = String(localized: "Session signed out.")
            await loadGrants()
        } catch { fail(error) }
    }
    func revokeGrant(_ row: Components.Schemas.DeviceGrant) async {
        guard canRequest, grants.contains(where: { $0.id == row.id }) else { return }
        grantGeneration += 1; grantsLoad = .ready
        busy = true; error = nil; notice = nil
        do {
            try await repository.revokeGrant(id: row.id); guard active else { return }
            if row.id == currentDeviceGrantID { invalidate(); await endSession([], "This device was signed out."); return }
            // DeviceGrant has no 'current' flag. Never infer current identity from ordering or platform.
            if currentDeviceGrantID == nil {
                do { try await repository.validateSession() }
                catch {
                    guard active else { return }
                    if AccountOperationFailure.isCancellation(error) { invalidate(); return }
                    invalidate(); await endSession([], "Device removed. Sign in again to refresh this session."); return
                }
            }
            guard active else { return }
            grants.removeAll { $0.id == row.id }; busy = false; notice = String(localized: "Device signed out."); if memberSelfServiceAvailable { await loadSessions() }
        } catch { fail(error) }
    }
    func changePassword(current: String, new: String, confirmation: String) async -> Bool {
        guard canRequest else { return false }
        guard !current.isEmpty, !new.isEmpty else { error = String(localized: "Enter your current password and a new password."); return false }
        guard new == confirmation else { error = String(localized: "Your new passwords don't match."); return false }
        busy = true; error = nil; notice = nil; defer { if active { busy = false } }
        do {
            try await repository.changePassword(current: current, new: new); guard active else { return false }
            // The endpoint returns an acknowledgement, not a replacement device grant.
            await passwordChanged(); guard active else { return false }
            notice = isDemo ? String(localized: "Password change preview complete. No password was changed.") : String(localized: "Password changed.")
            return true
        } catch { fail(error); return false }
    }
    func startAuthenticator() async {
        guard canStartMFA, validPassword else { return }; busy = true; error = nil
        let value = password; password = ""
        do {
            let challenge = try await repository.startMFA(password: value); guard active else { return }
            invalidate(); await beginSecurityEnrollment(challenge)
        } catch { fail(error) }
    }
    func regenerateRecovery() async {
        guard canRegenerateRecovery, validPassword else { return }; busy = true; error = nil
        let value = password; password = ""
        do {
            let result = try await repository.regenerateRecovery(password: value); guard active else { return }
            let codes = result.recovery_codes
            invalidate(); await endSession(codes, "Your previous sessions have ended. Save these recovery codes, then sign in again.")
        } catch { fail(error) }
    }
    func disableAuthenticator() async {
        guard canDisableMFA, validPassword else { return }; busy = true; error = nil
        let value = password; password = ""
        do {
            let result = try await repository.disableMFA(password: value); guard active else { return }
            invalidate(); await endSession([], result.enabled ? "Your previous sessions have ended. Sign in again to check two-step sign-in." : "Two-step sign-in was disabled. Your previous sessions have ended. Sign in again to continue.")
        } catch { fail(error) }
    }
    private var validPassword: Bool {
        guard !password.isEmpty, password.count <= 1024 else { error = String(localized: "Enter your current password."); return false }; return true
    }
    static func canonicalPhone(callingCode: String, number: String) -> String? {
        let calling = callingCode.hasPrefix("+") ? String(callingCode.dropFirst()) : callingCode
        guard (1...3).contains(calling.count), calling.first != "0",
              calling.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let incoming = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let international = incoming.hasPrefix("+")
        let raw = international ? String(incoming.dropFirst()) : incoming
        guard raw.allSatisfy({ ($0.isASCII && $0.isNumber) || " -()".contains($0) }) else { return nil }
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        guard !international || digits.hasPrefix(calling) else { return nil }
        let national = international ? String(digits.dropFirst(calling.count)) : digits
        guard national.count >= 6, calling.count + national.count <= 15 else { return nil }
        return "+" + calling + national
    }
    func sendPhoneCode() async {
        guard canRequest, now() >= resendAfter else { return }
        guard let value = pendingPhone ?? Self.canonicalPhone(callingCode: phoneCountry, number: phone) else { error = String(localized: "Enter a valid phone number."); return }
        busy = true; error = nil; code = ""
        do {
            _ = try await repository.startPhone(phone: value); guard active else { return }
            pendingPhone = value; phoneCooldown.resendAfter = now().addingTimeInterval(60); busy = false
            notice = isDemo ? String(localized: "Sample code sent in demo mode. No message was sent.") : String(localized: "Verification code sent.")
        } catch {
            if let deadline = APIError.retryDeadline(error), deadline > phoneCooldown.resendAfter { phoneCooldown.resendAfter = deadline }
            fail(error)
        }
    }
    func confirmPhone() async {
        guard canRequest, let pendingPhone else { return }
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { error = String(localized: "Enter the six-digit verification code."); return }
        let value = code; code = ""; busy = true; error = nil
        do {
            let result = try await repository.confirmPhone(phone: pendingPhone, code: value); guard active else { return }
            guard result.verified, result.phone_e164 == pendingPhone else { throw APIError(status: 0, code: "phone_verification_unconfirmed", detail: String(localized: "Phone verification wasn't confirmed. Request a new code and try again.")) }
            phoneStatus = result; self.pendingPhone = nil; phone = ""; busy = false
            notice = result.verified ? String(localized: "Phone number verified.") : String(localized: "This number could not be verified.")
        } catch {
            fail(error)
            if active && ![401, 403, 429].contains(APIError.status(error)) { self.error = String(localized: "Invalid or expired verification code.") }
        }
    }
    func changePhoneNumber() { guard !busy else { return }; pendingPhone = nil; code = ""; error = nil }
    func unlinkPhone() async {
        guard canRequest else { return }; busy = true; error = nil
        do {
            let result = try await repository.unlinkPhone(); guard active else { return }
            guard !result.verified, result.phone_e164.isEmpty else { throw APIError(status: 0, code: "phone_unlink_unconfirmed", detail: String(localized: "Phone removal wasn't confirmed. Check the current number before trying again.")) }
            phoneStatus = result; pendingPhone = nil; code = ""; phone = ""; busy = false; notice = String(localized: "Phone sign-in removed.")
        } catch { fail(error) }
    }
    func unlinkProvider(_ provider: String) async {
        guard canRequest, providers.contains(where: { $0.provider == provider }) else { return }; busy = true; error = nil; notice = nil
        providerGeneration += 1; providersLoad = .ready
        do {
            try await repository.unlinkProvider(provider); guard active else { return }
            providers.removeAll { $0.provider == provider }; busy = false; notice = String(localized: "Sign-in method removed.")
        } catch { fail(error) }
    }
    func cancelRenewal() async { await changeMembership(leave: false) }
    func leaveMakerspace() async { await changeMembership(leave: true) }
    private func changeMembership(leave: Bool) async {
        let reason = membershipReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard memberSelfServiceAvailable else { error = String(localized: "Membership self-service isn't available for this account."); return }
        guard canRequest, membership?.status.rawValue == "active", !reason.isEmpty, reason.count <= 1000 else { error = String(localized: "Add a reason of up to 1,000 characters."); return }
        membershipGeneration += 1; let generation = membershipGeneration; membershipLoad = .ready
        busy = true; error = nil; notice = nil; defer { if active { busy = false } }
        do {
            let result: Components.Schemas.MembershipAccount
            if leave {
                try await beforeLeave()
                guard active, generation == membershipGeneration, memberSelfServiceAvailable else {
                    if active { await leaveFailed() }
                    return
                }
                result = try await repository.leave(reason: reason)
            }
            else { result = try await repository.cancelRenewal(reason: reason) }
            guard active else { return }
            if result.status.rawValue == "revoked" { invalidate(); await membershipEnded(); return }
            guard generation == membershipGeneration, memberSelfServiceAvailable else { return }
            membership = result; membershipReason = ""; busy = false
            if !leave && result.renewal_cancelled_at != nil { notice = String(localized: "Membership renewal cancelled.") }
            else {
                error = String(localized: "This membership change wasn't confirmed. Refresh its status before trying again.")
                if leave { await leaveFailed() }
            }
        } catch { if leave, active { await leaveFailed() }; if generation == membershipGeneration { fail(error) } }
    }
    func requestExport() async {
        guard dataExportAvailable, canRequest else { return }; busy = true; error = nil; notice = nil; defer { if active { busy = false } }
        exportGeneration += 1; let generation = exportGeneration; exportsLoad = .ready
        do {
            let result = try await repository.requestExport(); guard active, generation == exportGeneration, dataExportAvailable else { return }
            exports.removeAll { $0.id == result.id }; exports.insert(result, at: 0); busy = false; exportsLoad = .ready
            notice = String(localized: "Export requested. Check its status when you're ready.")
        } catch { if generation == exportGeneration { fail(error) } }
    }
    func refreshExport(_ row: Components.Schemas.SubjectExport) async {
        guard dataExportAvailable, canRequest, exports.contains(where: { $0.id == row.id }) else { return }; busy = true; error = nil; defer { if active { busy = false } }
        exportGeneration += 1; let generation = exportGeneration; exportsLoad = .ready
        do {
            let result = try await repository.export(id: row.id); guard active, generation == exportGeneration, dataExportAvailable else { return }
            exports = exports.map { $0.id == result.id ? result : $0 }; busy = false
        } catch { if generation == exportGeneration { fail(error) } }
    }
    func canDownloadExport(_ row: Components.Schemas.SubjectExport, at date: Date? = nil) -> Bool {
        guard dataExportAvailable, active, let current = exports.first(where: { $0.id == row.id }) else { return false }
        return current.status.value1.rawValue == "available" && current.expires_at > (date ?? now())
    }
    func downloadExport(_ row: Components.Schemas.SubjectExport) async {
        guard dataExportAvailable, canRequest, !downloading, let current = exports.first(where: { $0.id == row.id }) else { return }
        guard canDownloadExport(current) else {
            if current.expires_at <= now() { error = String(localized: "This export expired. Request a new archive.") }
            return
        }
        downloadGeneration += 1; let generation = downloadGeneration; downloading = true; error = nil; archive = nil
        do {
            let bytes = try await repository.exportArchive(id: row.id); guard active, generation == downloadGeneration else { return }
            archive = try NativeFileTransfer.document(data: bytes, kind: .zip, suggestedName: isDemo ? "Space-Works-demo-export" : "Space-Works-data-export")
            downloading = false
        } catch {
            guard active, generation == downloadGeneration else { return }; downloading = false; fail(error)
            if let transfer = error as? NativeTransferError { self.error = transfer.errorDescription }
        }
    }
    private func fail(_ error: Error) { guard active else { return }; refuse(error); self.error = APIError.display(error); busy = false }
    private func refuse(_ error: Error) {
        if let deadline = APIError.retryDeadline(error), deadline > retryAfter {
            retryAfter = deadline; cooldownTask?.cancel()
            let sleep = cooldownSleep
            cooldownTask = Task { [weak self] in
                do {
                    while !Task.isCancelled, deadline > Date() {
                        let seconds = min(3600, max(0, deadline.timeIntervalSinceNow))
                        try await sleep(UInt64(seconds * 1_000_000_000))
                    }
                } catch { return }
                guard !Task.isCancelled, let self, self.active, self.retryAfter == deadline else { return }
                self.retryAfter = .distantPast
            }
        }
        if APIError.status(error) == 401 { invalidate() }
        else if APIError.status(error) == 403 { clearPrivateData(preservingBusy: true) }
    }
}
