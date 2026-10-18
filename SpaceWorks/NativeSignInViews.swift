import SwiftUI
import SpaceWorksAPI

/// The server's native minimum-version gate. Stored credentials are kept for the updated app.
struct UpdateRequiredView: View {
    let auth: AuthState
    let state: AppState
    var body: some View {
        ScrollView {
            SWCard {
                Image(systemName: "arrow.down.app").font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                Text("Update required").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("This version of the app is no longer supported by this server. Update the app to continue.").foregroundStyle(Color.swMuted)
                if let minimum = auth.minimumVersion {
                    Text("Required version: \(minimum) or later").brandFont(.headline).accessibilityIdentifier("minimum-version")
                }
                if let error = auth.error { SWError(message: error) }
                Button(auth.busy ? "Checking…" : "Check again") { Task { await auth.retryRestore() } }
                    .buttonStyle(SWPrimary()).disabled(auth.busy).accessibilityIdentifier("check-update")
                if !state.locked { Button("Change server") { state.changeServer() }.frame(minHeight: 48).disabled(auth.busy) }
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg).accessibilityIdentifier("update-required")
    }
}

/// Superadmin accounts are refused on phones and tablets (`device_superadmin_not_supported`).
struct WebConsoleNoticeView: View {
    let auth: AuthState
    var body: some View {
        ScrollView {
            SWCard {
                Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                Text("Use the web console").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("Superadmin accounts cannot sign in on a phone or tablet.").foregroundStyle(Color.swMuted)
                Button("Back to sign in") { auth.leaveWebConsoleNotice() }.buttonStyle(SWPrimary()).accessibilityIdentifier("web-console-back")
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg).accessibilityIdentifier("web-console")
    }
}

/// Only providers published in `PublicConfig.native` render. Each launch requests a fresh challenge and nonce.
struct ProviderSignInSection: View {
    let auth: AuthState
    @Binding var phone: PhoneSignInState?
    @State private var apple = AppleIdentity()
    @State private var organization = NativeOIDCSignIn()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let clientID = auth.googleClientID {
                GeometryReader { geometry in
                    GoogleProviderButton(wide: geometry.size.width >= 312) { google(clientID) }
                }.frame(height: 48).accessibilityIdentifier("provider-google")
            }
            if auth.appleEnabled {
                AppleProviderButton { signInWithApple() }.frame(height: 48).accessibilityIdentifier("provider-apple")
            }
            ForEach(auth.organizationProviders, id: \.key) { provider in
                Button { signIn(organization: provider) } label: {
                    Text("Continue with \(provider.display_name)").frame(maxWidth: .infinity, minHeight: 48)
                }.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
                    .accessibilityIdentifier("provider-\(provider.key)")
            }
            if auth.phoneEnabled {
                Button { phone = auth.phoneSignIn() } label: {
                    Label("Continue with phone", systemImage: "phone").frame(maxWidth: .infinity, minHeight: 48)
                }.overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("provider-phone")
            }
        }.disabled(auth.busy)
    }
    private func google(_ clientID: String) {
        Task {
            await auth.signIn(with: .google) { nonce in
                guard let controller = NativePresentation.topController else { throw NativeIdentity.unavailable }
                return try await NativeIdentity.google(clientID: clientID, nonce: nonce, presenting: controller)
            }
        }
    }
    private func signInWithApple() {
        Task {
            await auth.signIn(with: .apple) { nonce in
                guard let window = NativePresentation.window else { throw NativeIdentity.unavailable }
                return try await apple.credential(nonce: nonce, anchor: window)
            }
        }
    }
    private func signIn(organization provider: Components.Schemas.NativeOidc) {
        guard let slug = NativeOIDCClient.slug(fromKey: provider.key) else { return }
        Task {
            await auth.signIn(with: .oidc(slug: slug)) { nonce in
                guard let window = NativePresentation.window else { throw NativeIdentity.unavailable }
                return try await organization.credential(issuer: provider.issuer, clientID: provider.client_id, nonce: nonce, anchor: window)
            }
        }
    }
}

struct PhoneSignInView: View {
    @Bindable var form: PhoneSignInState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                SWCard {
                    Text("Continue with phone").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                    if form.step == .number {
                        Text("We'll send a verification code.").foregroundStyle(Color.swMuted)
                        Text("Phone number").brandFont(.headline)
                        TextField("Phone number", text: $form.number, prompt: Text(verbatim: "+91 98765 43210").foregroundColor(Color.swMuted))
                            .textContentType(.telephoneNumber).keyboardType(.phonePad).focused($focused)
                            .padding(16).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("phone-number")
                        Text("Include your country code.").brandFont(.caption).foregroundStyle(Color.swMuted)
                        if let error = form.error { SWError(message: error) }
                        Button(form.busy ? "Sending…" : "Send verification code") { Task { await form.send() } }
                            .buttonStyle(SWPrimary()).disabled(form.busy).accessibilityIdentifier("phone-send")
                    } else {
                        Text("Enter your verification code").brandFont(.title2, weight: .bold)
                        Text(verbatim: form.phone ?? "").foregroundStyle(Color.swMuted)
                        Text("Verification code").brandFont(.headline)
                        TextField("Verification code", text: $form.code)
                            .textContentType(.oneTimeCode).keyboardType(.numberPad).focused($focused)
                            .submitLabel(.go).onSubmit { Task { await form.verify() } }
                            // A complete code (typed or filled from Messages) verifies once; the button stays as a fallback.
                            .onChange(of: form.code) { _, value in
                                if value.count == 6, value.allSatisfy({ $0.isASCII && $0.isNumber }), !form.busy { focused = false; Task { await form.verify() } }
                            }
                            .padding(16).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("phone-code")
                        if let error = form.error { SWError(message: error) }
                        Button(form.busy ? "Verifying…" : "Verify") { Task { await form.verify() } }
                            .buttonStyle(SWPrimary()).disabled(form.busy).accessibilityIdentifier("phone-verify")
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Button(tick.date < form.resendAfter ? "Resend in \(max(1, Int(ceil(form.resendAfter.timeIntervalSince(tick.date)))))s" : "Send another code") {
                                Task { await form.send() }
                            }.frame(minHeight: 48).disabled(form.busy || tick.date < form.resendAfter)
                        }
                        Button("Change number") { form.changeNumber() }.frame(minHeight: 48).disabled(form.busy)
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48).disabled(form.busy) }
                    ToolbarItem(placement: .keyboard) { Button("Done") { focused = false } }
                }
        }.interactiveDismissDisabled(form.busy)
    }
}
