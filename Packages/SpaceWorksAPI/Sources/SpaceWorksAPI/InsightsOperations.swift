import Foundation
import OpenAPIRuntime

/// Member usage, the staff dashboard and SMS/WhatsApp consent. Callers bind the makerspace header with
/// `withMakerspace`; account restore is anonymous and never returns a session.
extension SpaceWorksService {
    public func memberUsage(makerspaceID: Int) async throws -> Components.Schemas.MemberUsage {
        try await client.api_v1_member_makerspaces_my_usage_retrieve(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func staffDashboard(makerspaceID: Int) async throws -> Components.Schemas.Dashboard {
        try await client.api_v1_admin_makerspace_dashboard_retrieve(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func messagingConsent(makerspaceID: Int) async throws -> Components.Schemas.MemberMessaging {
        try await client.api_v1_me_messaging_retrieve(.init(query: .init(makerspace: makerspaceID))).ok.body.json
    }
    public func setMessagingConsent(makerspaceID: Int, channel: Components.Schemas.Channel06eEnum,
                                    optIn: Bool) async throws -> Components.Schemas.MemberMessaging {
        let input = Components.Schemas.ConsentWrite(makerspace: makerspaceID, channel: channel, action: optIn ? .opted_in : .opted_out)
        return try await client.api_v1_me_messaging_consent_create(.init(body: .json(input))).ok.body.json
    }
    /// Phone restore of an archived account; the OTP came from phone login start with the same challenge.
    public func restoreAccountByPhone(phone: String, code: String, newPassword: String, challenge: String,
                                      attestationJSON: Data) async throws -> Components.Schemas.AccountRestoreResult {
        let input = Components.Schemas.AccountRestorePhone(phone: phone, delivery: .init(value1: .device),
            client_platform: .init(value1: .ios), challenge: challenge, code: code,
            attestation: .init(value1: try DeviceAttestation.payload(attestationJSON)), new_password: newPassword)
        return try await publicClient.api_v1_auth_account_restore_phone_create(.init(body: .json(input))).ok.body.json
    }
}
