import Foundation
import SpaceWorksAPI

protocol AccountRepository: Sendable {
    var isDemo: Bool { get }
    func grants() async throws -> [Components.Schemas.DeviceGrant]
    func revokeGrant(id: String) async throws
    func sessions(page: Int) async throws -> Components.Schemas.AccountSessionPage
    func revokeSession(id: String) async throws
    func membership() async throws -> Components.Schemas.MembershipAccount
    func leave(reason: String) async throws -> Components.Schemas.MembershipAccount
    func cancelRenewal(reason: String) async throws -> Components.Schemas.MembershipAccount
    func exports(page: Int) async throws -> Components.Schemas.SubjectExportList
    func requestExport() async throws -> Components.Schemas.SubjectExport
    func export(id: String) async throws -> Components.Schemas.SubjectExport
    func exportDownload(id: String) async throws -> Components.Schemas.DataExportDownloadUrl
    func exportArchive(id: String) async throws -> Data
    func mfa() async throws -> Components.Schemas.MFAStatus
    func startMFA(password: String) async throws -> Components.Schemas.MFAChallengeResponse
    func disableMFA(password: String) async throws -> Components.Schemas.MFAStatus
    func regenerateRecovery(password: String) async throws -> Components.Schemas.MFARecovery
    func startPhone(phone: String) async throws -> Components.Schemas.PhoneStartResponse
    func confirmPhone(phone: String, code: String) async throws -> Components.Schemas.PhoneStatus
    func unlinkPhone() async throws -> Components.Schemas.PhoneStatus
    func providers() async throws -> [Components.Schemas.SocialIdentity]
    func unlinkProvider(_ provider: String) async throws
    func changePassword(current: String, new: String) async throws
    func validateSession() async throws
}
extension AccountRepository { var isDemo: Bool { false } }

/// Caller owns clear/re-auth transitions after current grant/session revocation or MFA changes.
/// Scope remains captured across all actor suspension, including global account operations.
struct LiveAccountRepository: AccountRepository {
    let service: SpaceWorksService
    let expectedCredentials: CredentialSnapshot
    let makerspaceID: Int?
    let origin: ServerOrigin
    var onUnauthorized: @Sendable (String) async -> Void = { _ in }
    var onForbidden: @Sendable () async -> Void = {}

    private func checked<T: Sendable>(passwordVerification: Bool = false, global: Bool = false, _ work: @Sendable () async throws -> T) async throws -> T {
        // Catch and password-identity probes remain inside the owning installation's task scope.
        guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
        if await service.refresh.current() == nil {
            let failure = APIError(status: 401, code: "signed_out", detail: String(localized: "Please sign in again."))
            guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
            await onUnauthorized(failure.detail); throw failure
        }
        return try await service.withSession(expectedCredentials: expectedCredentials) {
            do {
                if global { return try await work() }
                return try await service.withMakerspace(try requireMakerspace(), operation: work)
            } catch {
                let original = error
                if Task.isCancelled || AccountOperationFailure.isCancellation(error) { throw original }
                guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
                let empty = await service.refresh.current() == nil
                if passwordVerification, APIError.status(original) == 401, !empty {
                    var verifiedIdentity = false
                    do {
                        _ = try await service.withSession(expectedCredentials: expectedCredentials) { try await service.me() }
                        verifiedIdentity = true
                    } catch {
                        if Task.isCancelled || AccountOperationFailure.isCancellation(error) { throw error }
                        guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
                        let probeEmpty = await service.refresh.current() == nil
                        if APIError.status(error) == 401 || probeEmpty { await onUnauthorized(APIError.display(error)) }
                        else if APIError.status(error) == 403 { await onForbidden() }
                        // An unavailable identity probe cannot turn an otherwise owned session
                        // into a confirmed401. Keep its real retry/offline failure actionable.
                        throw error
                    }
                    guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
                    if verifiedIdentity {
                        throw APIError(status: 0, code: "password_verification_failed", detail: APIError.display(original), retryAfter: APIError.retryDeadline(original))
                    }
                    throw original
                }
                guard await service.refresh.isSameInstallation(expectedCredentials) else { throw CancellationError() }
                if APIError.status(original) == 401 || empty { await onUnauthorized(APIError.display(original)) }
                else if APIError.status(original) == 403 { await onForbidden() }
                throw original
            }
        }
    }
    func grants() async throws -> [Components.Schemas.DeviceGrant] { try await checked(global: true) { try await service.accountGrants() } }
    func revokeGrant(id: String) async throws { try validUUID(id); try await checked(global: true) { try await service.accountRevokeGrant(id: id) } }
    func sessions(page: Int) async throws -> Components.Schemas.AccountSessionPage {
        try firstPage(page)
        let makerspaceID = try requireMakerspace()
        let result = try await checked { try await service.accountSessions(makerspaceID: makerspaceID) }
        try validateNext(result.next, path: "/api/v1/member/makerspaces/\(makerspaceID)/account/sessions"); return result
    }
    func revokeSession(id: String) async throws {
        let makerspaceID = try requireMakerspace()
        guard !id.isEmpty, id.utf8.count <= 512, !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw invalid(String(localized: "Choose a valid session.")) }
        try await checked { try await service.accountRevokeSession(makerspaceID: makerspaceID, id: id) }
    }
    func membership() async throws -> Components.Schemas.MembershipAccount { let makerspaceID = try requireMakerspace(); return try await checked { try await service.accountMembership(makerspaceID: makerspaceID) } }
    func leave(reason: String) async throws -> Components.Schemas.MembershipAccount {
        let makerspaceID = try requireMakerspace()
        let value = try validReason(reason); return try await checked { try await service.accountLeave(makerspaceID: makerspaceID, reason: value) }
    }
    func cancelRenewal(reason: String) async throws -> Components.Schemas.MembershipAccount {
        let makerspaceID = try requireMakerspace()
        let value = try validReason(reason); return try await checked { try await service.accountCancelRenewal(makerspaceID: makerspaceID, reason: value) }
    }
    func exports(page: Int) async throws -> Components.Schemas.SubjectExportList {
        try firstPage(page)
        let makerspaceID = try requireMakerspace()
        let result = try await checked { try await service.accountExports(makerspaceID: makerspaceID) }
        try validateNext(result.next, path: "/api/v1/member/makerspaces/\(makerspaceID)/account/exports"); return result
    }
    func requestExport() async throws -> Components.Schemas.SubjectExport { let makerspaceID = try requireMakerspace(); return try await checked { try await service.accountRequestExport(makerspaceID: makerspaceID) } }
    func export(id: String) async throws -> Components.Schemas.SubjectExport {
        let makerspaceID = try requireMakerspace()
        try validUUID(id); return try await checked { try await service.accountExport(makerspaceID: makerspaceID, id: id) }
    }
    func exportDownload(id: String) async throws -> Components.Schemas.DataExportDownloadUrl {
        let makerspaceID = try requireMakerspace()
        try validUUID(id)
        let result = try await checked { try await service.accountExportDownload(makerspaceID: makerspaceID, id: id) }
        guard result.expires_at > Date(), result.url.utf8.count <= 8192, !result.url.contains("\\"),
              !result.url.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: result.url, relativeTo: origin.url)?.absoluteURL,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              parts.scheme == origin.url.scheme, parts.host?.lowercased() == origin.url.host?.lowercased(),
              effectivePort(url) == effectivePort(origin.url), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw invalid(String(localized: "This export link is unavailable. Request a new link and try again.")) }
        let prefix = "/api/v1/data-exports/download/\(id)/"
        guard parts.percentEncodedPath.hasPrefix(prefix) else { throw invalid(String(localized: "This export link is unavailable. Request a new link and try again.")) }
        let token = String(parts.percentEncodedPath.dropFirst(prefix.count))
        guard !token.isEmpty, token.utf8.count <= 4096, !token.contains("/"),
              let decoded = token.removingPercentEncoding, !decoded.isEmpty,
              decoded != ".", decoded != "..", !decoded.contains("/"), !decoded.contains("\\"),
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw invalid(String(localized: "This export link is unavailable. Request a new link and try again."))
        }
        return result
    }
    func exportArchive(id: String) async throws -> Data {
        let makerspaceID = try requireMakerspace()
        let grant = try await exportDownload(id: id)
        guard let parts = URLComponents(string: grant.url),
              let token = parts.percentEncodedPath.split(separator: "/").last.flatMap({ String($0).removingPercentEncoding }) else {
            throw invalid(String(localized: "This export link is unavailable. Request a new link and try again."))
        }
        return try await checked {
            guard await service.makerspace.current() == makerspaceID,
                  await service.refresh.current() != nil else { throw CancellationError() }
            return try await service.accountExportArchive(id: id, token: token)
        }
    }
    func mfa() async throws -> Components.Schemas.MFAStatus { try await checked(global: true) { try await service.accountMFA() } }
    func startMFA(password: String) async throws -> Components.Schemas.MFAChallengeResponse {
        // Source rejects any device_grant here. Public A1 enrollment is only for a native
        // device-login challenge, which already carries server-owned attestation context.
        throw APIError(status: 0, code: "native_mfa_management_unavailable", detail: String(localized: "Enable two-step verification in your browser, then sign in again on this device."))
    }
    func disableMFA(password: String) async throws -> Components.Schemas.MFAStatus {
        try validPassword(password); return try await checked(passwordVerification: true, global: true) { try await service.accountDisableMFA(password: password) }
    }
    func regenerateRecovery(password: String) async throws -> Components.Schemas.MFARecovery {
        try validPassword(password); return try await checked(passwordVerification: true, global: true) { try await service.accountRegenerateRecovery(password: password) }
    }
    func startPhone(phone: String) async throws -> Components.Schemas.PhoneStartResponse {
        try validPhone(phone); return try await checked(global: true) { try await service.accountStartPhone(phone: phone) }
    }
    func confirmPhone(phone: String, code: String) async throws -> Components.Schemas.PhoneStatus {
        try validPhone(phone)
        guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw invalid(String(localized: "Enter the six-digit verification code.")) }
        return try await checked(global: true) { try await service.accountConfirmPhone(phone: phone, code: code) }
    }
    func unlinkPhone() async throws -> Components.Schemas.PhoneStatus { try await checked(global: true) { try await service.accountUnlinkPhone() } }
    func providers() async throws -> [Components.Schemas.SocialIdentity] { try await checked(global: true) { try await service.accountProviders() } }
    func unlinkProvider(_ provider: String) async throws {
        guard !provider.isEmpty, provider.utf8.count <= 200, !provider.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw invalid(String(localized: "Choose a linked sign-in provider.")) }
        try await checked(global: true) { try await service.accountUnlinkProvider(provider) }
    }
    func updateTemporaryPassword(current: String, new: String) async throws {
        try await checked(passwordVerification: true, global: true) { try await service.changePassword(current: current, new: new) }
    }
    func changePassword(current: String, new: String) async throws {
        try await service.withSession(expectedCredentials: expectedCredentials) {
            try await checked(passwordVerification: true, global: true) { try await service.changePassword(current: current, new: new) }
            // The acknowledgement has no replacement grant. Validate identity after it;
            // a failure here is session refusal, never a wrong-password classification.
            _ = try await checked(global: true) { try await service.me() }
        }
    }
    func validateSession() async throws { _ = try await checked(global: true) { try await service.me() } }

    private func requireMakerspace() throws -> Int {
        guard let makerspaceID, makerspaceID > 0 else { throw APIError(status: 403, code: "account_membership_required", detail: String(localized: "Choose an active makerspace membership to use this account option.")) }
        return makerspaceID
    }
    private func firstPage(_ page: Int) throws {
        guard page == 1 else { throw APIError(status: 0, code: "account_pagination_unavailable", detail: String(localized: "More account records are available in your browser. This server has not provided native pagination for them.")) }
    }
    private func validateNext(_ next: String?, path: String) throws {
        guard let next else { return }
        guard next.utf8.count <= 8192, !next.contains("\\"), let base = URL(string: path, relativeTo: origin.url)?.absoluteURL,
              let absolute = URL(string: next, relativeTo: base)?.absoluteURL, let url = try origin.nextPage(absolute.absoluteString),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: true), parts.percentEncodedPath == path else {
            throw invalid(String(localized: "The server returned an invalid account page."))
        }
    }
    private func validUUID(_ id: String) throws { guard UUID(uuidString: id) != nil else { throw invalid(String(localized: "Choose a valid account record.")) } }
    private func validReason(_ reason: String) throws -> String {
        let value = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 1000 else { throw invalid(String(localized: "Add a reason of up to 1,000 characters.")) }; return value
    }
    private func validPassword(_ password: String) throws { guard !password.isEmpty, password.count <= 1024 else { throw invalid(String(localized: "Enter your current password.")) } }
    private func validPhone(_ phone: String) throws { guard !phone.isEmpty, phone.count <= 32 else { throw invalid(String(localized: "Enter a valid phone number.")) } }
    private func effectivePort(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
    private func invalid(_ message: String) -> APIError { APIError(status: 0, code: "invalid_account_input", detail: message) }
}
