import SwiftUI
import SpaceWorksAPI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct AuthRoot: View {
    let state: AppState
    @State private var auth: AuthState
    @Environment(\.scenePhase) private var scenePhase
    init(state: AppState, origin: ServerOrigin) {
        self.state = state
        _auth = State(initialValue: AuthState(origin: origin))
    }
    var body: some View {
        Group {
            switch auth.stage {
            case .restoring: ProgressView("Opening your makerspace…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.swBg)
            case .signIn: SignInView(auth: auth, state: state)
            case .mfa, .recoveryCodes: MFAView(auth: auth)
            case .passwordChange: PasswordChangeView(auth: auth)
            case .signedIn:
                if auth.selectedID == nil { MakerspacePicker(auth: auth) }
                else { AppShell(state: state, auth: auth) }
            }
        }
        .task { await auth.restore() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await auth.foreground() } } }
    }
}

struct PasswordChangeView: View {
    let auth: AuthState
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    var body: some View {
        ScrollView {
            SWCard {
                Text("Choose a new password").font(.largeTitle.bold())
                Text("Replace your temporary password to continue.").foregroundStyle(Color.swMuted)
                PasswordControl(title: "Current password", text: $current, identifier: "current-password")
                PasswordControl(title: "New password", text: $new, newPassword: true, identifier: "new-password")
                PasswordControl(title: "Confirm password", text: $confirmation, newPassword: true, identifier: "confirm-password")
                if let error = auth.error { SWError(message: error) }
                Button(auth.busy ? "Updating…" : "Update password") {
                    Task { await auth.changePassword(current: current, new: new, confirmation: confirmation); current = ""; new = ""; confirmation = "" }
                }.buttonStyle(SWPrimary()).disabled(auth.busy)
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 48).disabled(auth.busy)
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}

struct SWCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.swPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.swLine))
    }
}
struct SWError: View {
    let message: String
    var body: some View {
        Label { Text(message).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle.fill") }
            .foregroundStyle(Color.swDanger).accessibilityIdentifier("auth-error")
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear { UIAccessibility.post(notification: .announcement, argument: message) }
            .onChange(of: message) { _, value in UIAccessibility.post(notification: .announcement, argument: value) }
    }
}
struct SWPrimary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 16)
            .foregroundStyle(Color.swOnAccent)
            .background(configuration.isPressed ? Color.swAccentActive : Color.swAccent, in: RoundedRectangle(cornerRadius: 10))
    }
}
struct SignInView: View {
    @Bindable var auth: AuthState
    let state: AppState
    @State private var showPassword = false
    @State private var passwordFocused = false
    @State private var accountForm: AccountAccessState?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .center, spacing: 40) {
                    VStack(alignment: .leading, spacing: 24) {
                        BrandWordmark(compact: geometry.size.height < 600)
                        Text("Welcome back.").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Sign in to your makerspace account.").foregroundStyle(Color.swMuted)
                        SWCard {
                            Text("Sign in").font(.title2.bold())
                            if auth.configuration == nil {
                                Text("Couldn't load sign-in options. Try again.").foregroundStyle(Color.swMuted)
                                if let error = auth.error { SWError(message: error) }
                                Button("Try again") { Task { await auth.retryRestore() } }.buttonStyle(SWPrimary())
                            } else if !auth.passwordEnabled {
                                Text("Sign-in isn't available here").font(.headline)
                                Text("Ask your makerspace for help, or check the server address.").foregroundStyle(Color.swMuted)
                            } else {
                            field("Email or username") {
                                TextField("Email or username", text: $auth.username,
                                          prompt: Text("Email or username").foregroundColor(Color.swMuted)).textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .submitLabel(.next).onSubmit { passwordFocused = true }.accessibilityIdentifier("username")
                            }
                            field("Password") {
                                HStack {
                                    PasswordEntry(text: $auth.password, visible: showPassword, identifier: "password", focus: $passwordFocused)
                                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                                        .accessibilityLabel(showPassword ? "Hide password" : "Show password").frame(minWidth: 48, minHeight: 48)
                                }
                            }
                            Button("Forgot password?") { accountForm = auth.accountForm(.requestReset) }.frame(minHeight: 48)
                            if let error = auth.error { SWError(message: error) }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Button(auth.busy ? "Signing in…" : "Sign in") { Task { await auth.signIn() } }
                                    .buttonStyle(SWPrimary()).disabled(auth.busy || (auth.retryAfter ?? .distantPast) > context.date)
                                    .accessibilityIdentifier("sign-in")
                            }
                            if auth.signupEnabled {
                                HStack { Text("New here?").foregroundStyle(Color.swMuted); Button("Create account") { accountForm = auth.accountForm(.signUp) }.frame(minHeight: 48) }
                            }
                            }
                        }.disabled(auth.busy)
                        if !state.locked { Button("Change server") { state.changeServer() }.frame(minHeight: 48).disabled(auth.busy) }
                    }.frame(maxWidth: 460)
                    if geometry.size.width >= 960 && geometry.size.height >= 600 && !typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 24) {
                            BrandWordmark(spacious: true)
                            Text("Less searching.\nMore making.").font(.custom("Unbounded-Regular", size: 24, relativeTo: .title2).weight(.medium))
                            Text("Borrow hardware. Make room for your next idea.").font(.title3)
                        }.padding(40).frame(maxWidth: 460, minHeight: 460, alignment: .leading)
                            .background(Color.swSuccess, in: RoundedRectangle(cornerRadius: 28)).foregroundStyle(Color.swOnSuccess)
                            .accessibilityHidden(true)
                    }
                }.padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $accountForm) { form in AccountAccessView(form: form) { auth.username = form.email; accountForm = nil } }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().padding(.horizontal, 12).frame(minHeight: 52)
                .background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
        }
    }
}

struct BrandWordmark: View {
    var compact = false
    var spacious = false
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if Brand.appName == "Space Works" {
            if compact || verticalSize == .compact || typeSize.isAccessibilitySize {
                Image("BrandSymbol").resizable().scaledToFit().frame(width: 52, height: 48)
                    .padding(12).accessibilityLabel("Space Works")
            } else {
                Image("BrandStacked").resizable().scaledToFit().frame(width: spacious ? 280 : 180, height: spacious ? 100 : 64)
                    .padding(16).accessibilityLabel("Space Works")
            }
        } else { Text(Brand.appName).font(.headline).foregroundStyle(Color.swAccentInk) }
    }
}

struct MFAView: View {
    @Bindable var auth: AuthState
    @State private var recoveryEntry = false
    @State private var codesSaved = false
    var body: some View {
        ScrollView {
            SWCard {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                if auth.stage == .recoveryCodes {
                    Text("Save your recovery codes").font(.largeTitle.bold())
                    Text("Keep these somewhere safe. Each code works once.").foregroundStyle(Color.swMuted)
                    ForEach(auth.recoveryCodes, id: \.self) { Text($0).monospacedDigit().textSelection(.enabled) }
                    Toggle("I've saved my recovery codes", isOn: $codesSaved).frame(minHeight: 48)
                    Button("Continue") { auth.confirmRecoveryCodes() }.buttonStyle(SWPrimary()).disabled(!codesSaved)
                } else {
                    Text(auth.mfa?.enrollment_required == true ? "Add extra security" : "Check your authenticator").font(.largeTitle.bold())
                    if let enrollment = auth.enrollment {
                        Text("Add this account to your authenticator app, then enter its six-digit code.").foregroundStyle(Color.swMuted)
                        QRCodeView(value: enrollment.provisioning_uri)
                        DisclosureGroup("Can't scan the code?") {
                            Text(enrollment.secret).monospacedDigit().textSelection(.enabled)
                            Button("Copy setup key") { UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: enrollment.secret]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]) }.frame(minHeight: 48)
                        }
                    } else {
                        Text(recoveryEntry ? "Enter one of your saved recovery codes." : "Enter the six-digit code from your authenticator app.").foregroundStyle(Color.swMuted)
                    }
                    Text(recoveryEntry ? "Recovery code" : "Authentication code").font(.headline)
                    TextField(recoveryEntry ? "Recovery code" : "Authentication code", text: $auth.code,
                              prompt: Text(recoveryEntry ? "Recovery code" : "Authentication code").foregroundColor(Color.swMuted))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().padding(16)
                        .background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("mfa-code")
                    if let error = auth.error { SWError(message: error) }
                    Button(auth.busy ? "Verifying…" : "Verify") { Task { await auth.verify() } }
                        .buttonStyle(SWPrimary()).disabled(auth.busy).accessibilityIdentifier("verify")
                    if auth.enrollment == nil {
                        Button(recoveryEntry ? "Use authenticator code" : "Use a recovery code") { recoveryEntry.toggle(); auth.code = "" }.frame(minHeight: 48).disabled(auth.busy)
                    }
                    Button("Back to sign in") { auth.backToSignIn() }.frame(minHeight: 48).disabled(auth.busy)
                }
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}
struct QRCodeView: View {
    let value: String
    var label = "Authenticator setup QR code"
    var body: some View {
        if let image = image {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 240)
                .padding(12).background(Color.white).accessibilityLabel(label)
        }
    }
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
struct MakerspacePicker: View {
    let auth: AuthState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a makerspace").font(.largeTitle.bold())
                if auth.memberships.isEmpty {
                    Text("You haven’t joined a makerspace yet.").foregroundStyle(Color.swMuted)
                }
                ForEach(auth.memberships, id: \.id) { membership in
                    Button { Task { await auth.select(membership.id) } } label: {
                        SWCard {
                            Text(membership.slug).font(.title2.bold())
                            Text(membership.role_name).foregroundStyle(Color.swMuted)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("makerspace-\(membership.id)")
                }
                if let error = auth.error { SWError(message: error) }
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 48)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}
