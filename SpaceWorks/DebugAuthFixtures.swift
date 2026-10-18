#if DEBUG
import Foundation

/// Contract-shaped fixtures for UI tests only, selected by explicit process launch flags.
enum DebugAuthFixtures {
    static let grant = #"{"id":"00000000-0000-0000-0000-000000000001","platform":"apple","app_id":"org.spaceworks.app","environment":"development","status":"active","attested_at":"2026-10-16T12:00:00Z","last_used_at":"2026-10-16T12:00:00Z","created_at":"2026-10-16T12:00:00Z"}"#
    static let membership = #"{"id":7,"slug":"demo-workshop","role":"member","role_id":1,"role_ids":[1],"role_slugs":["member"],"role_names":["Member"],"role_name":"Member","role_slug":"member","source":"membership","actions":[],"can_configure_machine_types":false,"is_machine_only":false,"can_refer":false,"can_verify":false,"verified_at":null,"referrals_enabled":false}"#
    static let secondMembership = membership.replacingOccurrences(of: #""id":7"#, with: #""id":8"#).replacingOccurrences(of: "demo-workshop", with: "community-lab")
    static var user: String { user(memberships: [membership, secondMembership]) }
    /// A native staff session whose first membership grants handover and review actions.
    static var staffUser: String {
        let staff = membership.replacingOccurrences(of: #""actions":[]"#, with: #""actions":["accept_request","reject_request","assign_box","issue_request","return_request","upload_evidence"]"#)
        return user(memberships: [staff, secondMembership], authority: "native_staff")
    }
    static func user(memberships: [String], superuser: Bool = false, authority: String = "member") -> String {
        "{\"session_authority\":\"\(authority)\",\"id\":12,\"username\":\"member\",\"email\":\"member@example.invalid\",\"display_name\":\"Maker\",\"phone\":\"\",\"email_verified\":true,\"role\":\"member\",\"is_superuser\":\(superuser),\"must_change_password\":false,\"makerspaces\":[\(memberships.joined(separator: ","))]}"
    }
    static var tokens: String { "{\"access\":\"test-access\",\"refresh\":\"test-refresh\",\"user\":\(user),\"device_grant\":\(grant)}" }
    static let mfa = #"{"mfa_required":true,"enrollment_required":false,"challenge":"test-mfa-challenge-of-valid-length","expires_in":300}"#
    static let config = #"{"email_enabled":false,"public_image_max_bytes":10485760,"password_login":{"member":true,"staff":true},"social_auth":{}}"#
    /// The schema's `native` discovery block: password and phone enabled, optional iOS minimum.
    static func nativeConfig(minimum: String? = nil) -> String {
        let value = minimum.map { "\"\($0)\"" } ?? "null"
        return #"{"email_enabled":false,"public_image_max_bytes":10485760,"password_login":{"member":true},"native":{"min_app_version":{"android":null,"ios":"# + value + #"},"providers":{"password":true,"phone":true,"google":null,"apple":null,"oidc":[]}}}"#
    }
    static let enrollment = #"{"secret":"TESTAUTHENTICATORKEY","provisioning_uri":"otpauth://totp/SpaceWorks:maker?secret=TESTAUTHENTICATORKEY&issuer=SpaceWorks","qr_data_url":""}"#
}
#endif
