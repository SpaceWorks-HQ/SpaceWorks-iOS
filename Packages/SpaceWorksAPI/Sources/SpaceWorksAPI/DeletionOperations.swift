import Foundation
import OpenAPIRuntime

/// Whole-account deletion and its server-owned recent-identity proof. These are global account
/// operations: callers run them inside `withSession`, without a makerspace header.
extension SpaceWorksService {
    public func accountDeletionPreview() async throws -> Components.Schemas.AccountDeletionPreview {
        try await client.api_v1_auth_account_deletion_retrieve().ok.body.json
    }
    /// The server rechecks every blocker. A conflict (409) is surfaced as an APIError; refetch the preview.
    public func deleteAccount() async throws -> Components.Schemas.AccountDeletionResult {
        try await client.api_v1_auth_account_deletion_create(.init(body: .json(.init(confirm: .DELETE)))).accepted.body.json
    }
    public func reauthenticationStatus() async throws -> Components.Schemas.ReauthenticationStatus {
        try await client.api_v1_auth_reauth_retrieve().ok.body.json
    }
    public func reauthenticate(password: String, code: String?) async throws -> Components.Schemas.ReauthenticationResult {
        try await client.api_v1_auth_reauth_create(.init(body: .json(.init(password: password, code: code?.isEmpty == false ? code : nil)))).ok.body.json
    }
    /// A separate reauthentication OTP for phone-only accounts, not phone link or login verification.
    public func reauthenticationPhoneStart() async throws -> Components.Schemas.ReauthenticationPhoneStarted {
        try await client.api_v1_auth_reauth_phone_start_create().ok.body.json
    }
    public func reauthenticationPhoneConfirm(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await client.api_v1_auth_reauth_phone_confirm_create(.init(body: .json(.init(token: token, code: code)))).ok.body.json
    }
    public func reauthenticationSocialStart(provider: String) async throws -> Components.Schemas.ReauthenticationSocialStarted {
        try await client.api_v1_auth_reauth_social_start_create(.init(body: .json(.init(provider: provider)))).ok.body.json
    }
    public func reauthenticationSocialComplete(state: String, nonce: String, idToken: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await client.api_v1_auth_reauth_social_complete_create(.init(body: .json(.init(state: state, nonce: nonce, id_token: idToken)))).ok.body.json
    }
    public func reauthenticationFactor(token: String, code: String) async throws -> Components.Schemas.ReauthenticationResult {
        try await client.api_v1_auth_reauth_social_factor_create(.init(body: .json(.init(token: token, code: code)))).ok.body.json
    }
}
