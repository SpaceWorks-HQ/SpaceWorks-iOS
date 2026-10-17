#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable final class DemoNotificationState {
    var enabled = false
    var permissionDenied = false
    var rotations = 0
    var feedback: String?
}

struct DemoNotificationsView: View {
    @Bindable var state: DemoNotificationState
    let makerspaceID: Int
    let route: (MobileLink) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SWCard {
                    Label("Notifications", systemImage: "bell.badge").font(.title2.bold())
                    Text("Demo only. Changes stay in this preview. No notifications will be sent.").foregroundStyle(Color.swMuted)
                    Toggle("Preview permission denied", isOn: $state.permissionDenied).frame(minHeight: 48)
                    if state.permissionDenied {
                        Text("Notifications are off for this device.").font(.headline)
                        Button("Open system settings") { state.feedback = String(localized: "In a connected app, this opens notification settings for your device.") }.frame(minHeight: 48)
                    } else {
                        Button(state.enabled ? "Turn off demo notifications" : "Enable notifications") { state.enabled.toggle(); state.feedback = state.enabled ? "Demo notifications are enabled." : "Demo notifications are off." }
                            .buttonStyle(SWPrimary()).accessibilityIdentifier("enable-demo-notifications")
                    }
                    if let feedback = state.feedback { Text(feedback).foregroundStyle(Color.swMuted).accessibilityIdentifier("notification-preview-feedback") }
                }
                SWCard {
                    Text("Preview an update").font(.title2.bold())
                    Text("Open sample updates from your makerspaces. Changes stay in this preview.").foregroundStyle(Color.swMuted)
                    Button("Open inventory update") { route(.init(makerspaceID: makerspaceID, destination: .product(1))) }.frame(minHeight: 48).accessibilityIdentifier("demo-push-product")
                    Button("Open update from another makerspace") { route(.init(makerspaceID: makerspaceID == 7 ? 8 : 7, destination: .inbox)) }.frame(minHeight: 48).accessibilityIdentifier("demo-push-other-space")
                    Button("Preview older notification") { route(.init(makerspaceID: makerspaceID, destination: .inbox)) }.frame(minHeight: 48)
                    Button("Preview unavailable item") { route(.init(makerspaceID: makerspaceID, destination: .product(99999))) }.frame(minHeight: 48)
                    Button("Preview unauthorized makerspace") { route(.init(makerspaceID: 999, destination: .inbox)) }.frame(minHeight: 48).accessibilityIdentifier("demo-push-denied")
                    Button("Preview device refresh") { state.rotations += 1; state.feedback = String(localized: "Demo notification settings refreshed. No notifications were sent.") }.frame(minHeight: 48)
                }.disabled(!state.enabled || state.permissionDenied)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Notifications")
    }
}
#endif
