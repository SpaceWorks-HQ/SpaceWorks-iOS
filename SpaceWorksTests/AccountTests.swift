import Foundation
import SpaceWorksAPI
import XCTest
@testable import SpaceWorks

#if DEBUG
@MainActor final class AccountTests: XCTestCase {
    private func state(_ repo: DemoAccountRepository = DemoAccountRepository(), cooldown: AccountAccessCooldown? = nil,
                       now: @escaping () -> Date = Date.init,
                       currentID: String? = nil, end: @escaping ([String], String?) async -> Void = { _, _ in },
                       left: @escaping () async -> Void = {}) -> AccountState {
        AccountState(repository: repo, makerspaceID: 7, makerspaceName: "Sample makerspace", selfServiceEnabled: true, exportEnabled: true, currentDeviceGrantID: currentID,
                     phoneCooldown: cooldown, now: now, endSession: end, membershipEnded: left)
    }
    func testExportBootstrapFeatureIsIndependentOfMembershipSelfServiceAndRequiresBothModules() async throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DebugMemberFixtures.bootstrap.utf8)) as? [String: Any])
        object["modules"] = ["membership", "member_accounts"]
        object["features"] = ["membership.self_export"]
        var source = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let exportOnly = MemberCapabilities(repository: DemoMemberActionsRepository(bootstrapJSON: source), makerspaceID: 7)
        await exportOnly.load(); XCTAssertTrue(exportOnly.exports); XCTAssertFalse(exportOnly.selfService)
        object["modules"] = ["membership"]
        source = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let missingModule = MemberCapabilities(repository: DemoMemberActionsRepository(bootstrapJSON: source), makerspaceID: 7)
        await missingModule.load(); XCTAssertFalse(missingModule.exports)
    }
    func testNoMembershipStillSupportsGlobalSecurityProvidersAndDevices() async {
        let account = AccountState(repository: DemoAccountRepository(), makerspaceID: nil, makerspaceName: "", selfServiceEnabled: true, exportEnabled: true)
        await account.loadSecurity(); await account.loadProviders(); await account.loadGrants()
        XCTAssertNotNil(account.mfa); XCTAssertFalse(account.providers.isEmpty); XCTAssertFalse(account.grants.isEmpty)
        await account.loadSessions(); await account.loadMembership(); await account.loadExports()
        XCTAssertFalse(account.memberSelfServiceAvailable); XCTAssertFalse(account.dataExportAvailable)
        XCTAssertEqual(account.sessionsLoad, .idle); XCTAssertNil(account.membership); XCTAssertEqual(account.exportsLoad, .idle)
    }
    func testBootstrapDisablingMemberServicesClearsTheirDataButRetainsGlobalAccountControls() async {
        let account = state(); await account.loadSessions(); await account.loadMembership(); await account.loadExports()
        await account.loadSecurity(); await account.loadGrants()
        XCTAssertFalse(account.sessions.isEmpty); XCTAssertFalse(account.exports.isEmpty); XCTAssertNotNil(account.membership)
        account.updateCapabilities(selfService: false, exports: false)
        XCTAssertTrue(account.sessions.isEmpty); XCTAssertTrue(account.exports.isEmpty); XCTAssertNil(account.membership); XCTAssertNil(account.archive)
        XCTAssertNotNil(account.mfa); XCTAssertFalse(account.grants.isEmpty); XCTAssertTrue(account.isActive)
    }
    func testPasswordChangeNeedsMatchingFieldsThenRefreshesIdentityOnlyAfterAcknowledgement() async {
        var refreshed = 0
        let account = AccountState(repository: DemoAccountRepository(), makerspaceID: nil, makerspaceName: "", passwordChanged: { refreshed += 1 })
        let mismatch = await account.changePassword(current: "DemoPass!123", new: "NewDemoPassword!", confirmation: "Different")
        XCTAssertFalse(mismatch); XCTAssertEqual(refreshed, 0)
        let wrong = await account.changePassword(current: "incorrect", new: "NewDemoPassword!", confirmation: "NewDemoPassword!")
        XCTAssertFalse(wrong); XCTAssertEqual(refreshed, 0); XCTAssertTrue(account.isActive)
        let updated = await account.changePassword(current: "DemoPass!123", new: "NewDemoPassword!", confirmation: "NewDemoPassword!")
        XCTAssertTrue(updated); XCTAssertEqual(refreshed, 1); XCTAssertEqual(account.notice, "Password change preview complete. No password was changed.")
    }
    func testWrongManagementPasswordPreservesKnownValidSessionAndClearsPassword() async {
        var ended = false
        let account = state(end: { _, _ in ended = true }); await account.loadSecurity()
        account.password = "wrong"; await account.regenerateRecovery()
        XCTAssertFalse(ended); XCTAssertTrue(account.isActive); XCTAssertEqual(account.password, "")
        XCTAssertNotNil(account.error); XCTAssertNotNil(account.mfa)
    }
    func testRecoveryReplacementClearsOldAccountStateBeforeOneTimeCodesAreHandedToOwner() async {
        var codes: [String] = []; var ended = false
        let account = state(end: { values, _ in codes = values; ended = true })
        await account.loadSecurity(); await account.loadSessions(); account.password = "DemoPass!123"
        await account.regenerateRecovery()
        XCTAssertTrue(ended); XCTAssertEqual(codes.count, 3); XCTAssertFalse(account.isActive)
        XCTAssertTrue(account.sessions.isEmpty); XCTAssertNil(account.mfa); XCTAssertEqual(account.password, "")
    }
    func testRequiredMFAHidesAndRefusesDisable() async {
        var ended = false
        let account = state(DemoAccountRepository(scenario: .requiredMFA), end: { _, _ in ended = true })
        await account.loadSecurity(); account.password = "DemoPass!123"
        XCTAssertFalse(account.canDisableMFA); await account.disableAuthenticator()
        XCTAssertFalse(ended); XCTAssertTrue(account.mfa?.enabled == true)
    }
    func testCurrentSessionUsesServerCurrentFlagAndEndsLocalAccess() async throws {
        var ended = false
        let account = state(end: { _, _ in ended = true }); await account.loadSessions()
        let row = try XCTUnwrap(account.sessions.first { $0.current }); await account.revokeSession(row)
        XCTAssertTrue(ended); XCTAssertFalse(account.isActive); XCTAssertTrue(account.sessions.isEmpty)
    }
    func testOtherSessionRevocationKeepsCurrentSession() async throws {
        var ended = false
        let account = state(end: { _, _ in ended = true }); await account.loadSessions()
        let row = try XCTUnwrap(account.sessions.first { !$0.current }); await account.revokeSession(row)
        XCTAssertFalse(ended); XCTAssertTrue(account.isActive); XCTAssertFalse(account.sessions.contains { $0.id == row.id })
        XCTAssertTrue(account.sessions.contains { $0.current })
    }
    func testUnknownCurrentGrantIsVerifiedAfterRevocationAndRevokedSessionSignsOut() async throws {
        var ended = false
        let account = state(end: { _, _ in ended = true }); await account.loadGrants()
        let row = try XCTUnwrap(account.grants.first { $0.id == "83000000-0000-4000-8000-000000000001" })
        await account.revokeGrant(row); XCTAssertTrue(ended); XCTAssertFalse(account.isActive)
    }
    func testOtherDeviceRevocationValidatesAndKeepsActiveSession() async throws {
        var ended = false
        let account = state(end: { _, _ in ended = true }); await account.loadGrants()
        let row = try XCTUnwrap(account.grants.first { $0.id == "83000000-0000-4000-8000-000000000002" })
        await account.revokeGrant(row); XCTAssertFalse(ended); XCTAssertTrue(account.isActive)
        XCTAssertFalse(account.grants.contains { $0.id == row.id })
    }
    func testPhoneCodeMustBeVerifiedBeforeDisplayingLinkedPhone() async {
        let account = state(); account.phone = "9876543210"; await account.sendPhoneCode()
        XCTAssertNil(account.phoneStatus); XCTAssertEqual(account.pendingPhone, "+919876543210")
        account.code = "000000"; await account.confirmPhone()
        XCTAssertNil(account.phoneStatus); XCTAssertEqual(account.code, ""); XCTAssertEqual(account.error, "Invalid or expired verification code.")
        account.code = "123456"; await account.confirmPhone()
        XCTAssertTrue(account.phoneStatus?.verified == true); XCTAssertEqual(account.phoneStatus?.phone_e164, "+919876543210"); XCTAssertNil(account.pendingPhone)
    }
    func testPhoneResendCooldownSurvivesFormAndMakerspaceStateRecreation() async {
        let cooldown = AccountAccessCooldown()
        let first = state(cooldown: cooldown); first.phone = "9876543210"; await first.sendPhoneCode()
        let deadline = first.resendAfter; first.changePhoneNumber()
        let second = state(cooldown: cooldown); second.phone = "9876543210"; await second.sendPhoneCode()
        XCTAssertEqual(second.resendAfter, deadline); XCTAssertNil(second.pendingPhone)
    }
    func testPhoneValidationRejectsNonDigitsAndTooLongInternationalNumber() async {
        let account = state(); account.phoneCountry = "+00"; account.phone = "9876543210"; await account.sendPhoneCode()
        XCTAssertNotNil(account.error); XCTAssertNil(account.pendingPhone)
        account.phoneCountry = "+91"; account.phone = "9876543210123456"; await account.sendPhoneCode(); XCTAssertNil(account.pendingPhone)
    }
    func testPhoneAutofillAcceptsFormattedNationalAndFullInternationalWithoutDuplicatingCountry() {
        XCTAssertEqual(AccountState.canonicalPhone(callingCode: "+91", number: "+91 98765 43210"), "+919876543210")
        XCTAssertEqual(AccountState.canonicalPhone(callingCode: "+91", number: "(98765) 432-10"), "+919876543210")
        XCTAssertEqual(AccountState.canonicalPhone(callingCode: "91", number: "9876543210"), "+919876543210")
    }
    func testPhoneAutofillRefusesConflictingCountryUnicodeDigitsAndEmbeddedPlus() {
        for number in ["+44 7700 900123", "९८७६५४३२१०", "987+6543210"] {
            XCTAssertNil(AccountState.canonicalPhone(callingCode: "+91", number: number))
        }
    }
    func testPhoneResendUsesExactPendingCanonicalNumberUntilUserChoosesChange() async {
        let cooldown = AccountAccessCooldown()
        let account = state(cooldown: cooldown); account.phone = "+91 98765 43210"
        await account.sendPhoneCode(); XCTAssertEqual(account.pendingPhone, "+919876543210")
        cooldown.resendAfter = .distantPast; account.phoneCountry = "+44"; account.phone = "7700900123"
        await account.sendPhoneCode(); XCTAssertEqual(account.pendingPhone, "+919876543210")
    }
    func testUnlinkPhoneUsesReturnedVerifiedStatus() async {
        let account = state(); account.phone = "9876543210"; await account.sendPhoneCode(); account.code = "123456"; await account.confirmPhone()
        await account.unlinkPhone(); XCTAssertTrue(account.phoneStatus?.verified == false); XCTAssertEqual(account.phoneStatus?.phone_e164, "")
    }
    func testProviderConflictAndCancellationKeepExistingMethods() async {
        let account = state(); await account.loadProviders()
        await account.previewProviderLink("apple", outcome: .conflict); XCTAssertEqual(account.providers.map(\.provider), ["google"])
        await account.previewProviderLink("apple", outcome: .cancelled); XCTAssertEqual(account.providers.map(\.provider), ["google"])
        await account.previewProviderLink("apple", outcome: .success); XCTAssertEqual(Set(account.providers.map(\.provider)), ["google", "apple"])
    }
    func testLastProviderRemovalRefusalDoesNotOptimisticallyRemoveIt() async {
        let account = state(); await account.loadProviders(); await account.unlinkProvider("google")
        XCTAssertNotNil(account.error); XCTAssertEqual(account.providers.map(\.provider), ["google"]); XCTAssertTrue(account.isActive)
    }
    func testLeaveRefusalPreservesMembershipAndProvidesReason() async {
        var left = false
        let account = state(DemoAccountRepository(scenario: .blockedMembership), left: { left = true })
        await account.loadMembership(); account.membershipReason = "Moving away"; await account.leaveMakerspace()
        XCTAssertFalse(left); XCTAssertEqual(account.membership?.status.rawValue, "active"); XCTAssertNotNil(account.error)
    }
    func testSelfServiceDisabledDuringPushCleanupAbortsLeaveAndReturnsOwnershipForSafeResume() async throws {
        let repository = DemoAccountRepository(); var resumed = 0; var ended = false
        var account: AccountState!
        account = AccountState(repository: repository, makerspaceID: 7, makerspaceName: "Sample", selfServiceEnabled: true,
            membershipEnded: { ended = true }, beforeLeave: { account.updateCapabilities(selfService: false, exports: false) }, leaveFailed: { resumed += 1 })
        await account.loadMembership(); account.membershipReason = "Moving away"; await account.leaveMakerspace()
        let actual = try await repository.membership()
        XCTAssertEqual(actual.status.rawValue, "active"); XCTAssertEqual(resumed, 1); XCTAssertFalse(ended)
        XCTAssertNil(account.membership); XCTAssertFalse(account.memberSelfServiceAvailable)
    }
    func testCancellingRenewalKeepsMembershipWhileLeavingEndsScope() async {
        var left = false
        let account = state(left: { left = true }); await account.loadMembership(); account.membershipReason = "Renew manually"
        await account.cancelRenewal(); XCTAssertEqual(account.membership?.status.rawValue, "active"); XCTAssertNotNil(account.membership?.renewal_cancelled_at); XCTAssertFalse(left)
        account.membershipReason = "Moving away"; await account.leaveMakerspace(); XCTAssertTrue(left); XCTAssertFalse(account.isActive)
    }
    func testExportIsPendingUntilExplicitStatusCheckAndArchiveIsDeletedOnScopeEnd() async throws {
        let account = state(); await account.requestExport()
        let pending = try XCTUnwrap(account.exports.first); XCTAssertEqual(pending.status.value1.rawValue, "pending")
        await account.downloadExport(pending); XCTAssertNil(account.archive)
        await account.refreshExport(pending); let available = try XCTUnwrap(account.exports.first)
        XCTAssertEqual(available.status.value1.rawValue, "available"); await account.downloadExport(available)
        let url = try XCTUnwrap(account.archive?.url); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        account.invalidate(); XCTAssertNil(account.archive); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testIdleExportDeadlineDisablesDownloadAndExpiredTapExplainsWithoutCreatingArchive() async throws {
        var clock = Date()
        let account = state(now: { clock }); await account.loadExports()
        let row = try XCTUnwrap(account.exports.first)
        clock = row.expires_at.addingTimeInterval(-1)
        XCTAssertTrue(account.canDownloadExport(row))
        clock = row.expires_at
        XCTAssertFalse(account.canDownloadExport(row))
        await account.downloadExport(row)
        XCTAssertNil(account.archive); XCTAssertEqual(account.error, "This export expired. Request a new archive.")
    }
    func testRetryAfterBlocksRepeatedActionsAndInvalidationErasesSecrets() async {
        let account = state(DemoAccountRepository(scenario: .throttled)); await account.loadMembership()
        XCTAssertFalse(account.canRequest); XCTAssertGreaterThan(account.retryAfter, Date())
        account.password = "secret"; account.code = "123456"; account.phone = "9876543210"; account.invalidate()
        XCTAssertEqual(account.password, ""); XCTAssertEqual(account.code, ""); XCTAssertEqual(account.phone, "")
    }
    func testHelpLinksRequireHTTPSAndRefuseCredentialURLs() {
        XCTAssertNil(AccountLinks.safe(URL(string: "http://example.com/privacy")))
        XCTAssertNil(AccountLinks.safe(URL(string: "https://user:pass@example.com/privacy")))
        XCTAssertNotNil(AccountLinks.safe(URL(string: "https://example.com/privacy")))
    }
}
#endif
