import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Optional device-owner lock for a signed-in account. It hides app content after backgrounding until
/// Face ID, Touch ID, Optic ID or the device passcode succeeds. It never stores or sends biometric data.
@MainActor @Observable
final class NativeAppLock {
    enum Kind: Equatable { case faceID, touchID, opticID, passcode, unavailable }
    let scope: String
    let kind: Kind
    private(set) var enabled: Bool
    private(set) var locked: Bool
    private(set) var busy = false
    private(set) var error: String?
    private let settings: UserDefaults
    private let evaluate: @MainActor (String) async -> Bool

    init(scope: String, settings: UserDefaults = .standard, kind: Kind = NativeAppLock.availableKind(),
         evaluate: @escaping @MainActor (String) async -> Bool = NativeAppLock.deviceOwner) {
        self.scope = scope; self.settings = settings; self.kind = kind; self.evaluate = evaluate
        let stored = kind != .unavailable && settings.bool(forKey: "app-lock." + scope)
        enabled = stored
        locked = stored // A cold launch with the lock on starts locked.
    }

    var available: Bool { kind != .unavailable }
    var title: String {
        switch kind {
        case .faceID: return String(localized: "Require Face ID")
        case .touchID: return String(localized: "Require Touch ID")
        case .opticID: return String(localized: "Require Optic ID")
        case .passcode, .unavailable: return String(localized: "Require device passcode")
        }
    }
    private var reason: String { String(localized: "Unlock your makerspace account.") }

    /// Turning the lock on proves the owner can unlock first; turning it off needs no proof.
    func setEnabled(_ value: Bool) async {
        guard available, !busy, value != enabled else { return }
        if value {
            busy = true; let allowed = await evaluate(reason); busy = false
            guard allowed else { error = String(localized: "App lock was not turned on."); return }
        }
        error = nil; enabled = value; locked = false
        settings.set(value, forKey: "app-lock." + scope)
    }

    func lock() { if enabled { locked = true } }

    func unlock() async {
        guard locked, !busy else { return }
        busy = true; error = nil
        let allowed = await evaluate(reason)
        busy = false
        if allowed { locked = false } else { error = String(localized: "Unlock to continue.") }
    }

    nonisolated static func availableKind() -> Kind {
        let context = LAContext()
        var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { return .unavailable }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    nonisolated static func deviceOwner(_ reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

struct AppLockView: View {
    let lock: NativeAppLock
    let signOut: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandWordmark()
                Image(systemName: lock.kind == .touchID ? "touchid" : lock.kind == .passcode ? "lock" : "faceid")
                    .font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                Text("Your account is locked").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("Unlock to continue.").foregroundStyle(Color.swMuted)
                if let error = lock.error, error != String(localized: "Unlock to continue.") { SWError(message: error) }
                Button(lock.busy ? "Unlocking…" : "Unlock") { Task { await lock.unlock() } }
                    .buttonStyle(SWPrimary()).disabled(lock.busy).accessibilityIdentifier("app-unlock")
                Button("Sign out", role: .destructive, action: signOut).frame(minHeight: 48).disabled(lock.busy)
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg).accessibilityIdentifier("app-lock")
    }
}
