#if DEBUG
import Foundation
import SpaceWorksAPI

/// Global sign-in methods follow the demo account; member records remain makerspace-specific.
struct DemoScopedAccountRepository: DemoAccountLinking {
    let global: DemoAccountRepository
    let member: DemoAccountRepository
    let isDemo = true
    func grants() async throws -> [Components.Schemas.DeviceGrant] { try await global.grants() }
    func revokeGrant(id: String) async throws -> Void { try await global.revokeGrant(id: id) }
    func sessions(page: Int) async throws -> Components.Schemas.AccountSessionPage { try await member.sessions(page: page) }
    func revokeSession(id: String) async throws -> Void { try await member.revokeSession(id: id) }
    func membership() async throws -> Components.Schemas.MembershipAccount { try await member.membership() }
    func leave(reason: String) async throws -> Components.Schemas.MembershipAccount { try await member.leave(reason: reason) }
    func cancelRenewal(reason: String) async throws -> Components.Schemas.MembershipAccount { try await member.cancelRenewal(reason: reason) }
    func exports(page: Int) async throws -> Components.Schemas.SubjectExportList { try await member.exports(page: page) }
    func requestExport() async throws -> Components.Schemas.SubjectExport { try await member.requestExport() }
    func export(id: String) async throws -> Components.Schemas.SubjectExport { try await member.export(id: id) }
    func exportDownload(id: String) async throws -> Components.Schemas.DataExportDownloadUrl { try await member.exportDownload(id: id) }
    func exportArchive(id: String) async throws -> Data { try await member.exportArchive(id: id) }
    func mfa() async throws -> Components.Schemas.MFAStatus { try await global.mfa() }
    func startMFA(password: String) async throws -> Components.Schemas.MFAChallengeResponse { try await global.startMFA(password: password) }
    func disableMFA(password: String) async throws -> Components.Schemas.MFAStatus { try await global.disableMFA(password: password) }
    func regenerateRecovery(password: String) async throws -> Components.Schemas.MFARecovery { try await global.regenerateRecovery(password: password) }
    func startPhone(phone: String) async throws -> Components.Schemas.PhoneStartResponse { try await global.startPhone(phone: phone) }
    func confirmPhone(phone: String, code: String) async throws -> Components.Schemas.PhoneStatus { try await global.confirmPhone(phone: phone, code: code) }
    func unlinkPhone() async throws -> Components.Schemas.PhoneStatus { try await global.unlinkPhone() }
    func providers() async throws -> [Components.Schemas.SocialIdentity] { try await global.providers() }
    func unlinkProvider(_ provider: String) async throws -> Void { try await global.unlinkProvider(provider) }
    func changePassword(current: String, new: String) async throws -> Void { try await global.changePassword(current: current, new: new) }
    func validateSession() async throws -> Void { try await global.validateSession() }
    func linkProvider(_ provider: String, outcome: DemoAccountLinkOutcome) async throws -> Components.Schemas.SocialIdentity { try await global.linkProvider(provider, outcome: outcome) }
}

@MainActor extension DemoSession {
    func accountState(makerspaceID: Int?) -> AccountState {
        let global: DemoAccountRepository
        if let repository = globalAccountRepository { global = repository }
        else { global = DemoAccountRepository(scenario: accountScenario); globalAccountRepository = global }
        let member: DemoAccountRepository
        if let makerspaceID, let repository = memberAccountRepositories[makerspaceID] { member = repository }
        else {
            member = DemoAccountRepository(scenario: accountScenario)
            if let makerspaceID { memberAccountRepositories[makerspaceID] = member }
        }
        let repository = DemoScopedAccountRepository(global: global, member: member)
        return AccountState(repository: repository, makerspaceID: makerspaceID,
            makerspaceName: makerspaceID.flatMap { [7: spaces[0], 8: spaces[1]][$0] } ?? String(localized: "Your account"),
            currentDeviceGrantID: "83000000-0000-4000-8000-000000000001",
            phoneCooldown: accountCooldown,
            beginSecurityEnrollment: { [weak self] _ in
                guard let self else { return }
                self.securityEnrollment = true; self.scenario = .enrollment; self.error = nil; self.code = ""; self.password = ""; self.stage = .mfa
            }, endSession: { [weak self] codes, message in self?.securityEnded(codes: codes, message: message) },
            membershipEnded: { [weak self] in
                guard let self, let makerspaceID else { return }
                self.availableSpaces.remove(makerspaceID - 7)
                if let next = self.availableSpaces.sorted().first { self.selectedSpace = next; self.stage = .makerspace }
                else { self.stage = .noMakerspaces }
            })
    }
    func routeAccountBlocker(_ blocker: DemoDeletionState.Blocker) {
        guard stage == .shell else { return }
        if let index = spaces.firstIndex(of: blocker.makerspace), availableSpaces.contains(index) { selectedSpace = index }
        pendingAccountFix = blocker
    }
    func securityEnded(codes: [String], message: String?) {
        password = ""; code = ""; error = nil; securityEnrollment = false
        securityCodes = codes; securityMessage = message; stage = .securityCompletion
    }
    func finishSecurityTransition() {
        securityCodes = []; securityMessage = nil; securityEnrollment = false; password = ""; code = ""; username = ""; error = nil; scenario = .password; stage = .signIn
    }
}
#endif
