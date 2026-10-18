import Foundation
import DeviceCheck
import CryptoKit
import SpaceWorksAPI

enum NativeAttestor {
    static var development: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    static func attest(_ challenge: String) async throws -> Data {
        #if DEBUG && targetEnvironment(simulator)
        return Data(#"{"type":"development"}"#.utf8)
        #else
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            throw APIError(status: 0, code: "attestation_unavailable", detail: String(localized: "This device cannot verify this app. Try a supported iPhone."))
        }
        let key = try await service.generateKey()
        let proof = try await service.attestKey(key, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        // PRD §7: base64 key ID and CBOR attestation, sent through the schema's open proof alternative.
        return try JSONSerialization.data(withJSONObject: ["type": "app_attest", "key_id": key, "attestation": proof.base64EncodedString()])
        #endif
    }
}
