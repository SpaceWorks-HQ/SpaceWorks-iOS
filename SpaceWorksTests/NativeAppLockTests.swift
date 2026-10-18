import XCTest
@testable import SpaceWorks

@MainActor final class NativeAppLockTests: XCTestCase {
    private func settings() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    func testTurningTheLockOnRequiresAProofAndPersistsPerAccount() async {
        let defaults = settings(); var allow = false; var prompts = 0
        let lock = NativeAppLock(scope: "https://spaceworks.example.12", settings: defaults, kind: .faceID) { _ in prompts += 1; return allow }
        XCTAssertEqual(lock.title, "Require Face ID")
        await lock.setEnabled(true)
        XCTAssertFalse(lock.enabled); XCTAssertEqual(lock.error, "App lock was not turned on.")
        allow = true; await lock.setEnabled(true)
        XCTAssertTrue(lock.enabled); XCTAssertFalse(lock.locked); XCTAssertEqual(prompts, 2)
        let relaunched = NativeAppLock(scope: "https://spaceworks.example.12", settings: defaults, kind: .faceID) { _ in true }
        XCTAssertTrue(relaunched.enabled); XCTAssertTrue(relaunched.locked, "A cold launch with the lock on starts locked")
        let otherAccount = NativeAppLock(scope: "https://spaceworks.example.13", settings: defaults, kind: .faceID) { _ in true }
        XCTAssertFalse(otherAccount.enabled)
    }

    func testBackgroundLocksAndOnlyASuccessfulProofUnlocks() async {
        var allow = true
        let lock = NativeAppLock(scope: "scope", settings: settings(), kind: .touchID) { _ in allow }
        lock.lock(); XCTAssertFalse(lock.locked, "A disabled lock never locks")
        await lock.setEnabled(true); lock.lock(); XCTAssertTrue(lock.locked)
        allow = false; await lock.unlock()
        XCTAssertTrue(lock.locked); XCTAssertEqual(lock.error, "Unlock to continue.")
        allow = true; await lock.unlock()
        XCTAssertFalse(lock.locked); XCTAssertNil(lock.error)
        await lock.setEnabled(false); lock.lock(); XCTAssertFalse(lock.locked)
    }

    func testUnavailableDeviceOwnerAuthenticationOffersNoLock() async {
        let lock = NativeAppLock(scope: "scope", settings: settings(), kind: .unavailable) { _ in XCTFail("No prompt without a device owner method"); return true }
        XCTAssertFalse(lock.available)
        await lock.setEnabled(true)
        XCTAssertFalse(lock.enabled)
    }
}
