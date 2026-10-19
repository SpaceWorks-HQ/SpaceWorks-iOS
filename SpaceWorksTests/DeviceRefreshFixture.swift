import Foundation
@testable import SpaceWorks

/// A successful native refresh must include the authoritative device grant.
enum DeviceRefreshFixture {
    static var rotated: String {
        "{\"access\":\"rotated-access\",\"refresh\":\"rotated-refresh\",\"device_grant\":\(DebugAuthFixtures.grant)}"
    }
}
