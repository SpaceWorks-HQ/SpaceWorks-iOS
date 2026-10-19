import SwiftUI

struct AccountPasswordView: View {
    let state: AccountState
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Change password").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
            Text("Choose a unique password. Your server checks its password policy.").foregroundStyle(Color.swMuted)
            if state.isDemo { Text("Demo only. Use DemoPass!123 as the current password. No password will be changed.").foregroundStyle(Color.swMuted) }
            SWCard {
                PasswordControl(title: String(localized: "Current password"), text: $current, identifier: "account-password-current")
                PasswordControl(title: String(localized: "New password"), text: $new, newPassword: true, identifier: "account-password-new")
                PasswordControl(title: String(localized: "Confirm password"), text: $confirmation, newPassword: true, identifier: "account-password-confirm")
                Text("If you don't have a current password, sign out and use Forgot password to recover access.").brandFont(.subheadline).foregroundStyle(Color.swMuted)
                if let error = state.error { SWError(message: error) }
                if let notice = state.notice { Label(notice, systemImage: "checkmark.circle").foregroundStyle(Color.swMuted).accessibilityIdentifier("account-password-notice") }
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    Button(state.busy ? "Updating…" : "Update password") { Task {
                        let updated = await state.changePassword(current: current, new: new, confirmation: confirmation)
                        current = ""; if updated { new = ""; confirmation = "" }
                    } }.buttonStyle(SWPrimary()).disabled(!state.canRequest || current.isEmpty || new.isEmpty || confirmation.isEmpty)
                        .accessibilityIdentifier("account-password-update")
                    if tick.date < state.retryAfter { Text("Try again after \(state.retryAfter.formatted(date: .omitted, time: .shortened)).").foregroundStyle(Color.swMuted) }
                }
            }.disabled(state.busy)
        }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity) }.background(Color.swBg).foregroundStyle(Color.swInk)
            .navigationTitle("Change password").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .onDisappear { current = ""; new = ""; confirmation = "" }
    }
}
