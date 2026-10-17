import Foundation
import OpenAPIRuntime

public enum AccountOperationFailure {
    /// Generated ClientError wraps task/scope cancellation; do not turn it into account revocation.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        if let client = error as? ClientError { return isCancellation(client.underlyingError) }
        return false
    }
}

extension SpaceWorksService {
    public func accountGrants() async throws -> [Components.Schemas.DeviceGrant] {
        try await client.api_v1_auth_device_grants_list().ok.body.json
    }
    public func accountRevokeGrant(id: String) async throws {
        _ = try await client.api_v1_auth_device_grants_destroy(.init(path: .init(grant_id: id))).noContent
    }
    /// The pinned schema declares no page query, despite returning a paginated envelope.
    public func accountSessions(makerspaceID: Int) async throws -> Components.Schemas.AccountSessionPage {
        try await client.api_v1_member_makerspaces_account_sessions_retrieve(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func accountRevokeSession(makerspaceID: Int, id: String) async throws {
        _ = try await client.api_v1_member_makerspaces_account_sessions_destroy(.init(path: .init(makerspace_id: makerspaceID, session_id: id))).noContent
    }
    public func accountMembership(makerspaceID: Int) async throws -> Components.Schemas.MembershipAccount {
        try await client.api_v1_member_makerspaces_account_membership_retrieve(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func accountLeave(makerspaceID: Int, reason: String) async throws -> Components.Schemas.MembershipAccount {
        try await client.api_v1_member_makerspaces_account_leave_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(.init(reason: reason)))).ok.body.json
    }
    public func accountCancelRenewal(makerspaceID: Int, reason: String) async throws -> Components.Schemas.MembershipAccount {
        try await client.api_v1_member_makerspaces_account_cancel_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(.init(reason: reason)))).ok.body.json
    }
    /// The pinned schema declares no page query, despite returning a paginated envelope.
    public func accountExports(makerspaceID: Int) async throws -> Components.Schemas.SubjectExportList {
        try await client.api_v1_member_makerspaces_account_exports_retrieve(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func accountRequestExport(makerspaceID: Int) async throws -> Components.Schemas.SubjectExport {
        try await client.api_v1_member_makerspaces_account_exports_create(.init(path: .init(makerspace_id: makerspaceID), body: .json(.init()))).accepted.body.json
    }
    public func accountExport(makerspaceID: Int, id: String) async throws -> Components.Schemas.SubjectExport {
        try await client.api_v1_member_makerspaces_account_exports_retrieve_2(.init(path: .init(job_id: id, makerspace_id: makerspaceID))).ok.body.json
    }
    public func accountExportDownload(makerspaceID: Int, id: String) async throws -> Components.Schemas.DataExportDownloadUrl {
        try await client.api_v1_member_makerspaces_account_exports_download_create(.init(path: .init(job_id: id, makerspace_id: makerspaceID))).ok.body.json
    }
    /// Consume a fresh, validated one-use grant through its documented public API operation.
    /// URLSessionTransport currently buffers first; this is an honest post-buffer collection cap.
    public func accountExportArchive(id: String, token: String) async throws -> Data {
        let response = try await publicClient.api_v1_data_exports_download_retrieve(.init(path: .init(job_id: id, token: token)))
        let body: HTTPBody
        switch try response.ok.body {
        case .application_zip(let value), .binary(let value): body = value
        }
        return try await Data(collecting: body, upTo: 25 * 1024 * 1024)
    }
    public func accountMFA() async throws -> Components.Schemas.MFAStatus {
        try await client.api_v1_auth_mfa_retrieve().ok.body.json
    }
    /// Kept as a generated operation seam. Current backend refuses this route for device grants.
    public func accountStartMFA(password: String) async throws -> Components.Schemas.MFAChallengeResponse {
        try await client.api_v1_auth_mfa_create(.init(body: .json(.init(password: password)))).ok.body.json
    }
    public func accountDisableMFA(password: String) async throws -> Components.Schemas.MFAStatus {
        try await client.api_v1_auth_mfa_disable_create(.init(body: .json(.init(password: password)))).ok.body.json
    }
    public func accountRegenerateRecovery(password: String) async throws -> Components.Schemas.MFARecovery {
        try await client.api_v1_auth_mfa_recovery_create(.init(body: .json(.init(password: password)))).ok.body.json
    }
    public func accountStartPhone(phone: String) async throws -> Components.Schemas.PhoneStartResponse {
        try await client.api_v1_auth_phone_link_start_create(.init(body: .json(.init(phone: phone)))).ok.body.json
    }
    public func accountConfirmPhone(phone: String, code: String) async throws -> Components.Schemas.PhoneStatus {
        try await client.api_v1_auth_phone_link_confirm_create(.init(body: .json(.init(phone: phone, code: code)))).ok.body.json
    }
    public func accountUnlinkPhone() async throws -> Components.Schemas.PhoneStatus {
        try await client.api_v1_auth_phone_destroy().ok.body.json
    }
    public func accountProviders() async throws -> [Components.Schemas.SocialIdentity] {
        try await client.api_v1_auth_social_providers_list().ok.body.json
    }
    public func accountUnlinkProvider(_ provider: String) async throws {
        _ = try await client.api_v1_auth_social_providers_destroy(.init(path: .init(provider: provider))).noContent
    }
}
