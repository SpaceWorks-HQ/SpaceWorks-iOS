import SwiftUI
import SpaceWorksAPI

struct AccountView: View {
    @Bindable var state: AccountState
    var privacyURL: URL?
    var supportURL: URL?
    #if DEBUG
    var onDemoDelete: (() -> Void)? = nil
    var onDemoFix: ((DemoDeletionState.Blocker) -> Void)? = nil
    #endif
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Account and security").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
            Text("Manage your sign-in, devices, membership, and personal data.").foregroundStyle(Color.swMuted)
            if state.isDemo { Label("Demo account · sample data", systemImage: "info.circle").foregroundStyle(Color.swMuted) }
            SWCard {
                NavigationLink { AccountPasswordView(state: state) } label: { AccountMenuRow(title: "Change password", detail: String(localized: "Use your current password to set a new one"), icon: "key") }.accessibilityIdentifier("account-password")
                NavigationLink { AccountSecurityView(state: state) } label: { AccountMenuRow(title: "Two-step sign-in", detail: String(localized: "Authenticator and recovery codes"), icon: "lock.shield") }.accessibilityIdentifier("account-security")
                NavigationLink { AccountPhoneView(state: state) } label: { AccountMenuRow(title: "Phone sign-in", detail: String(localized: "Verify or remove a phone number"), icon: "phone") }.accessibilityIdentifier("account-phone")
                NavigationLink { AccountProvidersView(state: state) } label: { AccountMenuRow(title: "Connected sign-in methods", detail: String(localized: "Review your linked providers"), icon: "person.crop.circle.badge.checkmark") }.accessibilityIdentifier("account-providers")
                NavigationLink { AccountDevicesView(state: state) } label: { AccountMenuRow(title: "Devices", detail: String(localized: "Review your native app sessions"), icon: "iphone") }.accessibilityIdentifier("account-devices")
                if state.memberSelfServiceAvailable {
                    NavigationLink { AccountSessionsView(state: state) } label: { AccountMenuRow(title: "Sessions", detail: String(localized: "Review this makerspace's active sessions"), icon: "desktopcomputer.and.iphone") }.accessibilityIdentifier("account-sessions")
                    NavigationLink { AccountMembershipView(state: state) } label: { AccountMenuRow(title: "Your membership", detail: state.makerspaceName, icon: "person.text.rectangle") }.accessibilityIdentifier("account-membership")
                }
                if state.dataExportAvailable {
                    NavigationLink { AccountExportsView(state: state) } label: { AccountMenuRow(title: "Your data", detail: String(localized: "Request and download an export"), icon: "square.and.arrow.down") }.accessibilityIdentifier("account-exports")
                }
                if state.makerspaceID == nil { Text("Join a makerspace to manage membership records here.").foregroundStyle(Color.swMuted) }
            }
            SWCard {
                Text("Privacy and help").brandFont(.title2, weight: .bold)
                NavigationLink("App guide") { AppGuideView(isDemo: state.isDemo) }.frame(minHeight: 48).accessibilityIdentifier("app-guide")
                if let url = AccountLinks.safe(privacyURL) { Link("Privacy policy", destination: url).frame(minHeight: 48) }
                else { Text("Your makerspace hasn't provided a privacy policy link.").foregroundStyle(Color.swMuted) }
                if let url = AccountLinks.safe(supportURL) { Link("Contact support", destination: url).frame(minHeight: 48) }
                else { Text("Ask your makerspace for its support contact.").foregroundStyle(Color.swMuted) }
                Text("Account deletion").brandFont(.headline)
                #if DEBUG
                if state.isDemo, let onDemoDelete {
                    NavigationLink("Preview account deletion") {
                        DemoDeletionView(onFix: onDemoFix.map { route in { blocker in route(blocker); dismiss() } }, onDelete: onDemoDelete)
                    }.frame(minHeight: 48).accessibilityIdentifier("account-delete-preview")
                } else {
                    Text("Account deletion isn't available on this server yet. Contact your makerspace for help.").foregroundStyle(Color.swMuted)
                }
                #else
                Text("Account deletion isn't available on this server yet. Contact your makerspace for help.").foregroundStyle(Color.swMuted)
                #endif
            }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk).navigationTitle("Account and security").navigationBarTitleDisplayMode(.inline)
    }
}

enum AccountLinks {
    static func safe(_ value: URL?) -> URL? {
        guard let value, value.scheme == "https", value.host?.isEmpty == false, value.user == nil, value.password == nil else { return nil }; return value
    }
}

private struct AccountMenuRow: View {
    let title: LocalizedStringKey; let detail: String; let icon: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Decorative glyphs must not squeeze scaled words into narrow columns.
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).brandFont(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: detail).brandFont(.subheadline).foregroundStyle(Color.swMuted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: icon).font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) { Text(title).brandFont(.headline); Text(verbatim: detail).brandFont(.subheadline).foregroundStyle(Color.swMuted) }
                    Spacer(minLength: 0); Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
        }.foregroundStyle(Color.swInk).padding(.vertical, 12).frame(minHeight: 64)
    }
}

private struct AccountMessages: View {
    let state: AccountState
    var body: some View {
        if let error = state.error { SWError(message: error).accessibilityIdentifier("account-error") }
        if let notice = state.notice { Label(notice, systemImage: "info.circle").foregroundStyle(Color.swMuted).accessibilityIdentifier("account-notice") }
        if state.busy { ProgressView("Working…") }
        if Date() < state.retryAfter { Text("Try again after \(state.retryAfter.formatted(date: .omitted, time: .standard)).").foregroundStyle(Color.swMuted) }
    }
}

private struct AccountFeedback: View {
    let load: AccountState.Load; let retry: () async -> Void
    var body: some View {
        switch load { case .loading: ProgressView("Loading…")
        case .failed(let message): SWError(message: message); Button("Try again") { Task { await retry() } }.frame(minHeight: 48)
        default: EmptyView() }
    }
}

private struct AccountSecurityView: View {
    @Bindable var state: AccountState
    @State private var focused = false
    @State private var action: String?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Two-step sign-in").brandFont(.largeTitle, weight: .bold)
            Text("Use an authenticator as an extra check when you sign in.").foregroundStyle(Color.swMuted)
            AccountFeedback(load: state.securityLoad) { await state.loadSecurity() }
            AccountMessages(state: state)
            if let mfa = state.mfa {
                SWCard {
                    Label(mfa.enabled ? "Authenticator enrolled" : "Authenticator not enrolled", systemImage: "lock.shield").brandFont(.headline)
                    if mfa.required { Text("Your account requires two-step sign-in.").foregroundStyle(Color.swMuted) }
                    if !mfa.available && !mfa.enabled { Text("Two-step sign-in is unavailable on this server.").foregroundStyle(Color.swMuted) }
                    if !mfa.enabled && mfa.available && !state.isDemo { Text("Enable two-step sign-in in your makerspace's web portal, then sign in again on this device.").foregroundStyle(Color.swMuted) }
                }
                if mfa.enabled || state.canStartMFA {
                    Text("Current password").brandFont(.headline)
                    if state.isDemo { Text("Use DemoPass!123 in this demo. No real security setting changes.").brandFont(.subheadline).foregroundStyle(Color.swMuted) }
                    PasswordControl(title: String(localized: "Current password"), text: $state.password, identifier: "account-current-password", focus: $focused).disabled(state.busy)
                    Text("Changing your authenticator or recovery codes ends your existing sessions.").foregroundStyle(Color.swMuted)
                    if state.canStartMFA { Button("Enroll authenticator") { action = "enroll" }.buttonStyle(SWPrimary()).disabled(state.password.isEmpty) }
                    if mfa.enabled && mfa.available { Button("Regenerate recovery codes") { action = "recovery" }.frame(minHeight: 48).disabled(!state.canRegenerateRecovery || state.password.isEmpty).accessibilityIdentifier("account-regenerate-recovery") }
                    if mfa.enabled && !mfa.required { Button("Disable two-step sign-in", role: .destructive) { action = "disable" }.frame(minHeight: 48).disabled(!state.canDisableMFA || state.password.isEmpty) }
                }
            }
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Two-step sign-in").navigationBarTitleDisplayMode(.inline).task { await state.loadSecurity() }
            .confirmationDialog(action == "recovery" ? "Replace your recovery codes?" : action == "disable" ? "Disable two-step sign-in?" : "Enroll your authenticator?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                Button("Continue") { let selected = action; action = nil; Task {
                    if selected == "recovery" { await state.regenerateRecovery() }
                    else if selected == "disable" { await state.disableAuthenticator() }
                    else { await state.startAuthenticator() }
                } }
                Button("Cancel", role: .cancel) { action = nil }
            } message: { Text("Your existing sessions will end after this change.") }
            .onDisappear { state.password = "" }
    }
}

struct AccountSecurityCompletionView: View {
    let codes: [String]
    let message: String
    let continueToSignIn: () -> Void
    @State private var saved = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text(codes.isEmpty ? "Sign in again" : "Save your recovery codes").brandFont(.largeTitle, weight: .bold)
            Text(message).foregroundStyle(Color.swMuted)
            if !codes.isEmpty {
                SWCard { Text(codes.joined(separator: "\n")).brandFont(.body, weight: .medium).monospacedDigit().textSelection(.enabled).privacySensitive() }
                Text("Keep these codes somewhere safe. Each code can be used once.").foregroundStyle(Color.swMuted)
                Toggle("I saved my recovery codes", isOn: $saved).frame(minHeight: 48).accessibilityIdentifier("account-recovery-saved")
            }
            Button("Continue to sign in", action: continueToSignIn).buttonStyle(SWPrimary()).disabled(!codes.isEmpty && !saved).accessibilityIdentifier("account-security-continue")
        }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity) }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk).interactiveDismissDisabled()
    }
}

private struct AccountPhoneView: View {
    @Bindable var state: AccountState
    @State private var unlink = false
    private enum Field: Hashable { case country, phone, code }
    @FocusState private var focused: Field?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Phone sign-in").brandFont(.largeTitle, weight: .bold)
            Text("Verify a number to use it for sign-in.").foregroundStyle(Color.swMuted)
            AccountMessages(state: state)
            if let status = state.phoneStatus, status.verified { Label(status.phone_e164, systemImage: "checkmark.seal").brandFont(.headline) }
            if let pending = state.pendingPhone {
                Text("Enter the code sent to \(pending)").brandFont(.headline)
                TextField("Verification code", text: $state.code).textContentType(.oneTimeCode).keyboardType(.numberPad).modifier(AccountInput()).focused($focused, equals: .code).disabled(state.busy).accessibilityIdentifier("account-phone-code")
                if state.isDemo { Text("Use 123456 in this demo. No message was sent.").brandFont(.subheadline).foregroundStyle(Color.swMuted) }
                Button("Verify phone number") { Task { await state.confirmPhone() } }.buttonStyle(SWPrimary()).disabled(!state.canRequest).accessibilityIdentifier("account-phone-verify")
                Button("Change number") { state.changePhoneNumber() }.frame(minHeight: 48).disabled(state.busy)
            } else {
                Text("Country calling code").brandFont(.headline)
                TextField("Calling code", text: $state.phoneCountry).keyboardType(.phonePad).modifier(AccountInput()).focused($focused, equals: .country).disabled(state.busy)
                Text("Phone number").brandFont(.headline)
                TextField("Phone number", text: $state.phone).textContentType(.telephoneNumber).keyboardType(.phonePad).modifier(AccountInput()).focused($focused, equals: .phone).disabled(state.busy).accessibilityIdentifier("account-phone-number")
            }
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                Button(tick.date < state.resendAfter ? CooldownCopy.resendButton(until: state.resendAfter, now: tick.date) : state.pendingPhone == nil ? "Send verification code" : "Send another code") { Task { await state.sendPhoneCode() } }
                    .frame(minHeight: 48).disabled(!state.canRequest || tick.date < state.resendAfter).accessibilityIdentifier("account-phone-send")
            }
            Button("Remove linked phone", role: .destructive) { unlink = true }.frame(minHeight: 48).disabled(!state.canRequest)
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Phone sign-in").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar {
                if focused != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { focused = nil }
                            .accessibilityLabel(Text("Done")).accessibilityIdentifier("account-phone-keyboard-done")
                    }
                }
            }
            .confirmationDialog("Remove phone sign-in?", isPresented: $unlink, titleVisibility: .visible) { Button("Remove phone", role: .destructive) { Task { await state.unlinkPhone() } }; Button("Cancel", role: .cancel) {} }
            .onDisappear { state.code = "" }
    }
}

private struct AccountProvidersView: View {
    @Bindable var state: AccountState
    @State private var removing: String?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Connected sign-in methods").brandFont(.largeTitle, weight: .bold)
            AccountFeedback(load: state.providersLoad) { await state.loadProviders() }; AccountMessages(state: state)
            ForEach(state.providers, id: \.provider) { provider in
                SWCard {
                    Text(NativeStatusCopy.label(provider.provider)).brandFont(.headline)
                    Text("Connected \(provider.created_at.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Color.swMuted)
                    Button("Remove sign-in method", role: .destructive) { removing = provider.provider }.frame(minHeight: 48).disabled(!state.canRequest)
                }
            }
            if state.providersLoad == .ready && state.providers.isEmpty { Text("No connected providers.").foregroundStyle(Color.swMuted) }
            Text("Connect a new provider in your makerspace's web portal. Your existing sign-in methods remain available here.").foregroundStyle(Color.swMuted)
            #if DEBUG
            if state.isDemo { DemoAccountProviderLinks(state: state) }
            #endif
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Sign-in methods").navigationBarTitleDisplayMode(.inline).task { await state.loadProviders() }
            .confirmationDialog("Remove this sign-in method?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let provider = removing { Button("Remove", role: .destructive) { removing = nil; Task { await state.unlinkProvider(provider) } } }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: { Text("Make sure you can still sign in another way. Your makerspace may refuse to remove your last method.") }
    }
}

private struct AccountSessionsView: View {
    @Bindable var state: AccountState
    @State private var session: Components.Schemas.AccountSession?
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            Text("Sessions").brandFont(.largeTitle, weight: .bold); AccountMessages(state: state)
            AccountFeedback(load: state.sessionsLoad) { await state.loadSessions() }
            ForEach(state.sessions, id: \.id) { row in
                SWCard {
                    Label(row.kind.rawValue == "device" ? "Device session" : "Browser session", systemImage: row.kind.rawValue == "device" ? "iphone" : "globe").brandFont(.headline)
                    if row.current { Text("This session").foregroundStyle(Color.swAccentInk).brandFont(.headline) }
                    Text("Started \(row.created_at.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted)
                    if let last = row.last_used_at { Text("Last used \(last.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted) }
                    Button(row.current ? "Sign out this session" : "Sign out session", role: .destructive) { session = row }.frame(minHeight: 48).disabled(!state.canRequest).accessibilityIdentifier(row.current ? "account-revoke-current-session" : "account-revoke-session-\(row.id)")
                }
            }
            if state.sessionsHaveMore { Text("More sessions are available in your makerspace's web portal.").foregroundStyle(Color.swMuted) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Sessions").navigationBarTitleDisplayMode(.inline)
            .task { await state.loadSessions() }.refreshable { await state.loadSessions() }
            .confirmationDialog("Sign out this session?", isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } }), titleVisibility: .visible) {
                if let row = session { Button("Sign out", role: .destructive) { session = nil; Task { await state.revokeSession(row) } } }; Button("Cancel", role: .cancel) { session = nil }
            }

    }
}

private struct AccountDevicesView: View {
    @Bindable var state: AccountState
    @State private var grant: Components.Schemas.DeviceGrant?
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            Text("Devices").brandFont(.largeTitle, weight: .bold)
            Text("These are native app sessions on your account. Browser sessions are managed separately by your makerspace.").foregroundStyle(Color.swMuted)
            AccountMessages(state: state)
            Text("Registered devices").brandFont(.title2, weight: .bold)
            AccountFeedback(load: state.grantsLoad) { await state.loadGrants() }
            ForEach(state.grants, id: \.id) { row in
                SWCard {
                    Text(NativeStatusCopy.label(row.platform)).brandFont(.headline)
                    if state.currentDeviceGrantID == row.id { Text("This device").brandFont(.headline).foregroundStyle(Color.swAccentInk) }
                    Text(NativeStatusCopy.label(row.status)); Text("Last used \(row.last_used_at.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted)
                    Button("Sign out device", role: .destructive) { grant = row }.frame(minHeight: 48).disabled(!state.canRequest || row.status != "active").accessibilityIdentifier("account-revoke-device-\(row.id)")
                }
            }

            if state.grantsLoad == .ready && state.grants.isEmpty { Text("No devices found.").foregroundStyle(Color.swMuted) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Devices").navigationBarTitleDisplayMode(.inline)
            .task { await state.loadGrants() }.refreshable { await state.loadGrants() }
            .confirmationDialog("Sign out this device?", isPresented: Binding(get: { grant != nil }, set: { if !$0 { grant = nil } }), titleVisibility: .visible) {
                if let row = grant { Button("Sign out device", role: .destructive) { grant = nil; Task { await state.revokeGrant(row) } } }; Button("Cancel", role: .cancel) { grant = nil }
            }
    }
}

private struct AccountMembershipView: View {
    @Bindable var state: AccountState
    @State private var decision: String?
    @FocusState private var reasonFocused: Bool
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text(state.makerspaceName).brandFont(.largeTitle, weight: .bold); AccountMessages(state: state)
            AccountFeedback(load: state.membershipLoad) { await state.loadMembership() }
            if let membership = state.membership {
                Text(NativeStatusCopy.label(membership.status.rawValue)).brandFont(.headline)
                if let date = membership.renewal_cancelled_at { Text("Renewal cancelled \(date.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Color.swMuted) }
                if membership.status.rawValue == "active" {
                    Text("Reason").brandFont(.headline)
                    TextField("Tell your makerspace why", text: $state.membershipReason, axis: .vertical).focused($reasonFocused).lineLimit(3...6).modifier(AccountInput()).disabled(state.busy).accessibilityIdentifier("account-membership-reason")
                    Text("Leaving ends your access to this makerspace. Outstanding loans or charges may need to be resolved first.").foregroundStyle(Color.swMuted)
                    if membership.renewal_cancelled_at == nil { Button("Cancel membership renewal") { decision = "renewal" }.frame(minHeight: 48).disabled(!state.canRequest || state.membershipReason.isEmpty) }
                    Button("Leave makerspace", role: .destructive) { decision = "leave" }.frame(minHeight: 48).disabled(!state.canRequest || state.membershipReason.isEmpty).accessibilityIdentifier("account-leave-makerspace")
                }
            }
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Your membership").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar {
                if reasonFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { reasonFocused = false }
                            .accessibilityLabel(Text("Done")).accessibilityIdentifier("account-membership-keyboard-done")
                    }
                }
            }.task { await state.loadMembership() }
            .alert(decision == "leave" ? "Leave this makerspace?" : "Cancel membership renewal?", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), presenting: decision) { selectedDecision in
                Button(selectedDecision == "leave" ? String(localized: "Leave") : String(localized: "Stop renewal"), role: .destructive) { let leave = selectedDecision == "leave"; decision = nil; Task { if leave { await state.leaveMakerspace() } else { await state.cancelRenewal() } } }; Button("Cancel", role: .cancel) { decision = nil }
            }
    }
}

private struct AccountInput: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(minHeight: 48).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).foregroundStyle(Color.swInk)
    }
}

private struct AccountExportsView: View {
    @Bindable var state: AccountState
    @State private var share = false
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            Text("Your data").brandFont(.largeTitle, weight: .bold)
            Text("Request an export of your personal data held by this makerspace. Keep downloaded files somewhere private.").foregroundStyle(Color.swMuted)
            AccountMessages(state: state); AccountFeedback(load: state.exportsLoad) { await state.loadExports() }
            Button("Request data export") { Task { await state.requestExport() } }.buttonStyle(SWPrimary()).disabled(!state.canRequest).accessibilityIdentifier("account-request-export")
            if state.downloading { ProgressView("Preparing your archive…") }
            ForEach(state.exports, id: \.id) { row in
                SWCard {
                    Text(row.created_at, format: .dateTime.day().month().year()).brandFont(.headline)
                    Text(NativeStatusCopy.label(row.status.value1.rawValue)).foregroundStyle(Color.swMuted)
                    if !row.failure_detail.isEmpty { SWError(message: row.failure_detail) }
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                    if state.canDownloadExport(row, at: tick.date) {
                        Text("Available until \(row.expires_at.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted)
                        Button("Download export") { Task { await state.downloadExport(row) } }.frame(minHeight: 48).disabled(!state.canRequest || state.downloading).accessibilityIdentifier("account-download-export")
                    } else if ["pending", "running"].contains(row.status.value1.rawValue) {
                        Button("Check export status") { Task { await state.refreshExport(row) } }.frame(minHeight: 48).disabled(!state.canRequest).accessibilityIdentifier("account-check-export")
                    } else if row.expires_at <= tick.date { Text("This export expired. Request a new archive.").foregroundStyle(Color.swMuted).accessibilityIdentifier("account-export-expired") }
                    }
                }
            }
            if state.exportsHaveMore { Text("More exports are available in your makerspace's web portal.").foregroundStyle(Color.swMuted) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Your data").navigationBarTitleDisplayMode(.inline).task { await state.loadExports() }.refreshable { await state.loadExports() }
            .onChange(of: state.archive?.id) { _, _ in share = false }
            .sheet(item: $state.archive) { file in
                NavigationStack {
                    ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "doc.zipper").font(.largeTitle).accessibilityHidden(true)
                        Text(state.isDemo ? "Demo data export" : "Your data export").brandFont(.title, weight: .bold)
                        Text("Save this archive to a private location or share it with someone you trust.").foregroundStyle(Color.swMuted)
                        Button("Save or share archive") { share = true }.buttonStyle(SWPrimary()).accessibilityIdentifier("account-share-export")
                    }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }.background(Color.swBg).accessibilityIdentifier("account-export-scroll")
                        .navigationTitle("Data export").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { state.archive = nil } } }
                        .sheet(isPresented: $share) { NativeDocumentShare(file: file) }
                }
            }
    }
}
