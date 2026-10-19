import Foundation
import OpenAPIRuntime

/// A server-published native provider. OIDC operations address the configured provider slug.
public enum NativeSocialProvider: Sendable, Equatable {
    case google, apple, oidc(slug: String)
    /// The nonce operation's documented provider key (`oidc:{slug}` for configured OIDC).
    public var nonceKey: String {
        switch self {
        case .google: return "google"
        case .apple: return "apple"
        case .oidc(let slug): return "oidc:" + slug
        }
    }
}

extension SpaceWorksService {
    /// Member device delivery; the nonce is bound to this attestation challenge.
    public func socialNonce(provider: NativeSocialProvider, challenge: String) async throws -> Components.Schemas.SocialNonceResponse {
        let input = Components.Schemas.SocialNonce(provider: provider.nonceKey, surface: .member, delivery: .device,
                                                    client_platform: .ios, challenge: challenge)
        return try await publicClient.api_v1_auth_social_nonce_create(.init(body: .json(input))).ok.body.json
    }

    public func socialSignIn(provider: NativeSocialProvider, idToken: String, nonce: String, challenge: String,
                             attestationJSON: Data, authorizationCode: String? = nil,
                             appleName: String? = nil) async throws -> Components.Schemas.SocialLoginResponse {
        let input = Components.Schemas.SocialLogin(authorization_code: authorizationCode, id_token: idToken, nonce: nonce,
            surface: .member, delivery: .device, client_platform: .ios, apple_name: appleName, challenge: challenge,
            attestation: .init(value1: try DeviceAttestation.payload(attestationJSON)))
        switch provider {
        case .google:
            return try await publicClient.api_v1_auth_social_google_create(.init(body: .json(input))).ok.body.json
        case .apple:
            return try await publicClient.api_v1_auth_social_apple_create(.init(body: .json(input))).ok.body.json
        case .oidc(let slug):
            return try await publicClient.api_v1_auth_social_oidc_create(.init(path: .init(slug: slug), body: .json(input))).ok.body.json
        }
    }

    /// The start response is uniform and never discloses whether an account exists.
    public func phoneSignInStart(phone: String, challenge: String) async throws {
        let input = Components.Schemas.PhoneLoginStart(phone: phone, delivery: .init(value1: .device),
                                                       client_platform: .init(value1: .ios), challenge: challenge)
        _ = try await publicClient.api_v1_auth_phone_login_start_create(.init(body: .json(input))).ok.body.json
    }

    public func phoneSignInConfirm(phone: String, code: String, challenge: String,
                                   attestationJSON: Data) async throws -> Components.Schemas.PhoneLoginResult {
        let input = Components.Schemas.PhoneLoginConfirm(phone: phone, delivery: .init(value1: .device),
            client_platform: .init(value1: .ios), challenge: challenge, code: code,
            attestation: .init(value1: try DeviceAttestation.payload(attestationJSON)))
        return try await publicClient.api_v1_auth_phone_login_confirm_create(.init(body: .json(input))).ok.body.json
    }

    /// Revokes browser sessions, device grants and their push destinations on this server.
    public func signOutEverywhere() async throws -> Components.Schemas.LogoutAllResponse {
        try await client.api_v1_auth_logout_all_create().ok.body.json
    }
}

/// Native device completions must carry a refresh token and a device grant with a UUID id.
public enum NativeDeviceCompletion {
    public static func grantID<T: Encodable>(_ grant: T?) -> UUID? {
        guard let grant, let data = try? JSONEncoder().encode(grant),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else { return nil }
        return UUID(uuidString: id)
    }
    public static func tokens<G: Encodable>(access: String, refresh: String?, grant: G?, surface: String? = nil) -> TokenPair? {
        guard let refresh, !refresh.isEmpty, !access.isEmpty, surface != "verification_only", grantID(grant) != nil else { return nil }
        return TokenPair(access: access, refresh: refresh)
    }
}
