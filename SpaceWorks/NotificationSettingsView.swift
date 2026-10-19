import SwiftUI
import UserNotifications

/// OS delivery permission and account-level server registration are separate controls.
struct NotificationSettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: NotificationSettingsState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SWCard(contentPadding: dynamicTypeSize.isAccessibilitySize ? 12 : 24) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "bell.badge").accessibilityHidden(true)
                                Text("Notifications").frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Label("Notifications", systemImage: "bell.badge")
                        }
                    }.brandFont(.title2, weight: .bold)
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    Text("Keep up with requests, bookings, and important makerspace updates. Your inbox is always available.").foregroundStyle(Color.swMuted)
                    if !state.registration.configured {
                        Text("Notifications are not configured for this build. Your inbox is still available.").foregroundStyle(Color.swMuted)
                    } else if state.permissionDenied {
                        Text("Notifications are off for this device.").brandFont(.headline)
                        Button("Open system settings") { state.openSettings() }.frame(minHeight: 48)
                    } else {
                        Text(state.registration.enabled ? "Notifications are enabled for this account." : "Enable notifications when you're ready.").foregroundStyle(Color.swMuted)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button(state.busy ? "Updating…" : state.error != nil || state.registration.error != nil ? "Retry" : state.registration.enabled ? "Refresh" : "Enable notifications") {
                                Task { if state.registration.enabled { await state.refresh() } else { await state.enable() } }
                            }
                                .buttonStyle(SWPrimary()).disabled(state.busy || context.date < state.retryAfter)
                                .accessibilityIdentifier("enable-notifications")
                            if context.date < state.retryAfter { Text("Try again after \(state.retryAfter.formatted(date: .omitted, time: .shortened)).").foregroundStyle(Color.swMuted) }
                        }
                    }
                    if state.registration.enabled {
                        Text("Updates are enabled for \(state.registration.registeredMakerspaces.count) makerspaces.").foregroundStyle(Color.swMuted)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button("Turn off for this account") { Task { await state.disable() } }.frame(minHeight: 48).disabled(state.busy || context.date < state.retryAfter)
                        }
                    }
                    if let error = state.error ?? state.registration.error { SWError(message: error) }
                }
                SWCard { Text("Choose which updates you receive in Communication preferences. Required safety messages remain available in your inbox.").foregroundStyle(Color.swMuted) }
            }.padding(dynamicTypeSize.isAccessibilitySize ? 12 : 24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
            .task { await state.prepare() }
    }
}
