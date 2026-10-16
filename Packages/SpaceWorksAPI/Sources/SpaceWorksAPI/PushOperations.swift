import Foundation
import OpenAPIRuntime

public enum PushOperationFailure {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        if let client = error as? ClientError { return isCancellation(client.underlyingError) }
        return false
    }
}

extension SpaceWorksService {
    public func registerNativePush(token: String, environment: Components.Schemas.EnvironmentEnum) async throws -> Components.Schemas.PushDevice {
        let response = try await client.api_v1_integrations_push_devices_create(.init(body: .json(.init(token: token, provider: .apns, environment: environment))))
        switch response {
        case .ok(let value): return try value.body.json
        case .created(let value): return try value.body.json
        default: throw APIError(status: 0, code: "push_registration_unavailable", detail: "Notifications could not be registered. Your inbox is still available.")
        }
    }
    public func unregisterNativePush(deviceID: Int) async throws {
        _ = try await client.api_v1_integrations_push_devices_destroy(.init(path: .init(device_id: deviceID))).noContent
    }
}
