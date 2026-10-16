#if DEBUG
import Foundation

/// Contract-shaped fixtures for UI tests only, selected by explicit process launch flags.
enum DebugAuthFixtures {
    static let grant = #"{"id":"00000000-0000-0000-0000-000000000001","platform":"apple","app_id":"org.spaceworks.app","environment":"development","status":"active","attested_at":"2026-10-16T12:00:00Z","last_used_at":"2026-10-16T12:00:00Z","created_at":"2026-10-16T12:00:00Z"}"#
    static let membership = #"{"id":7,"slug":"demo-workshop","role":"member","role_id":1,"role_name":"Member","role_slug":"member","source":"membership","actions":[],"can_configure_machine_types":false,"is_machine_only":false,"can_refer":false,"can_verify":false,"verified_at":null,"referrals_enabled":false}"#
    static let secondMembership = membership.replacingOccurrences(of: #""id":7"#, with: #""id":8"#).replacingOccurrences(of: "demo-workshop", with: "community-lab")
    static var user: String { user(memberships: [membership, secondMembership]) }
    static func user(memberships: [String], superuser: Bool = false) -> String {
        "{\"id\":12,\"username\":\"member\",\"email\":\"member@example.invalid\",\"display_name\":\"Maker\",\"phone\":\"\",\"email_verified\":true,\"role\":\"member\",\"is_superuser\":\(superuser),\"must_change_password\":false,\"makerspaces\":[\(memberships.joined(separator: ","))]}"
    }
    static var tokens: String { "{\"access\":\"test-access\",\"refresh\":\"test-refresh\",\"user\":\(user),\"device_grant\":\(grant)}" }
    static let mfa = #"{"mfa_required":true,"enrollment_required":false,"challenge":"test-mfa-challenge-of-valid-length","expires_in":300}"#
    static let config = #"{"email_enabled":false,"public_image_max_bytes":10485760,"password_login":{"member":true,"staff":true},"social_auth":{}}"#
    static let enrollment = #"{"secret":"TESTAUTHENTICATORKEY","provisioning_uri":"otpauth://totp/SpaceWorks:maker?secret=TESTAUTHENTICATORKEY&issuer=SpaceWorks","qr_data_url":""}"#
}
#endif
