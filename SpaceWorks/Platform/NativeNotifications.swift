import CoreFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

/// Notification content is a routing hint. The caller must revalidate membership and fetch API data.
struct NotificationHint: Equatable {
    let makerspaceID: Int
    let version: Int
    let eventID: String?
    let inboxRowID: Int?
    let relativeLink: String?

    init?(payload: [AnyHashable: Any]) {
        guard let id = Self.positiveID(payload["makerspace_id"]) else { return nil }
        makerspaceID = id
        version = Int(Self.string(payload["v"]) ?? "1") ?? 0
        eventID = version == 2 ? Self.string(payload["event_id"]).flatMap { $0.count <= 256 ? $0 : nil } : nil
        inboxRowID = version == 2 ? Self.positiveID(payload["inbox_row_id"]) : nil
        if version == 2, let raw = Self.string(payload["link"]), raw.utf8.count <= 2048,
           !raw.contains("\\"), !raw.contains("%"),
           raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           let link = URLComponents(string: raw), link.scheme == nil, link.host == nil,
           link.query == nil, link.fragment == nil, link.path.hasPrefix("/"), !link.path.hasPrefix("//"),
           !link.path.split(separator: "/").contains("..") {
            relativeLink = link.path
        } else { relativeLink = nil }
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    private static func positiveID(_ value: Any?) -> Int? {
        guard let text = string(value), let number = Int(text), number > 0 else { return nil }
        return number
    }
}

@MainActor @Observable
final class NativeNotifications {
    static let shared = NativeNotifications()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var token: String?
    private(set) var error: String?
    private(set) var pendingHint: NotificationHint?
    var onTokenChanged: ((String) -> Void)?
    var onTap: ((NotificationHint) -> Void)? {
        didSet { deliverPendingHint() }
    }
    var onForegroundHint: ((NotificationHint) -> Void)?

    func requestPermission() async {
        error = nil
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch { self.error = String(localized: "Notifications could not be enabled. Try again in Settings.") }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(_ data: Data) {
        let value = data.map { String(format: "%02x", $0) }.joined()
        guard !value.isEmpty else { return }
        token = value
        error = nil
        onTokenChanged?(value)
    }

    func registrationFailed() { error = String(localized: "Push registration is unavailable. Your inbox is still available.") }

    /// Preserve a cold-launch tap until authentication and membership routing have been installed.
    func receive(_ hint: NotificationHint) {
        pendingHint = hint
        deliverPendingHint()
    }

    /// Foreground content is never shown from the untrusted APNs body. The owner may refresh its current inbox.
    func receivedInForeground(_ hint: NotificationHint) { onForegroundHint?(hint) }

    private func deliverPendingHint() {
        guard let hint = pendingHint, let handler = onTap else { return }
        pendingHint = nil
        handler(hint)
    }

    /// Call after removing server registration IDs. No prior user's notification routing survives logout.
    func reset() {
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        token = nil
        error = nil
        pendingHint = nil
        onTokenChanged = nil
        onTap = nil
        onForegroundHint = nil
    }
}

final class NativeNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in NativeNotifications.shared.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in NativeNotifications.shared.registrationFailed() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let hint = NotificationHint(payload: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let hint { NativeNotifications.shared.receive(hint) }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let hint = NotificationHint(payload: notification.request.content.userInfo)
        Task { @MainActor in
            if let hint { NativeNotifications.shared.receivedInForeground(hint) }
            // Backend payloads are hints, not displayable or authoritative content.
            completionHandler([])
        }
    }
}
