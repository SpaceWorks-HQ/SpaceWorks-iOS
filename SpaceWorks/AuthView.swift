import SwiftUI
import SpaceWorksAPI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct AuthRoot: View {
    let state: AppState
    let linkRouter: MobileLinkRouter
    let origin: ServerOrigin
    @State private var auth: AuthState
    @State private var routingOwner = UUID()
    @Environment(\.scenePhase) private var scenePhase
    init(state: AppState, origin: ServerOrigin, linkRouter: MobileLinkRouter) {
        self.state = state; self.origin = origin; self.linkRouter = linkRouter
        _auth = State(initialValue: AuthState(origin: origin))
    }
    var body: some View {
        ZStack {
            if auth.endingSession {
                ProgressView("Signing out…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.swBg)
            } else {
            switch auth.stage {
            case .restoring: ProgressView("Opening your makerspace…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.swBg)
            case .signIn: SignInView(auth: auth, state: state)
            case .mfa, .recoveryCodes: MFAView(auth: auth)
            case .passwordChange: PasswordChangeView(auth: auth)
            case .securityCompletion:
                AccountSecurityCompletionView(codes: auth.recoveryCodes, message: auth.securityMessage ?? "", continueToSignIn: auth.finishSecurityCompletion)
            case .signedIn:
                if auth.selectedID == nil { AccountMakerspaceLanding(auth: auth) }
                else { AppShell(state: state, auth: auth, linkRouter: linkRouter) }
            }
            }
        }
        .nativeFeedback(auth.feedback)
        .task { await auth.restore(); bindRouting() }
        .onChange(of: auth.stage) { _, _ in bindRouting() }
        .onChange(of: auth.user?.id) { _, _ in bindRouting() }
        .onChange(of: auth.foregroundHintRevision) { _, _ in Task { await auth.processForegroundHint() } }
        .onChange(of: auth.busy) { _, busy in if !busy { Task { await auth.processForegroundHint() } } }
        .onDisappear { linkRouter.unbind(owner: routingOwner); Task { await auth.stopNotifications() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await auth.foreground() } } }
    }
    private func bindRouting() {
        NativeNotifications.shared.onTap = { hint in linkRouter.receive(hint) }
        if auth.stage == .signedIn, let id = auth.user?.id {
            linkRouter.bind(account: origin.url.absoluteString + ".account.\(id)", refresh: { try await auth.freshMembershipIDs() }, select: { try await auth.selectForLink($0) }, resolveLegacy: { legacy in
                _ = try await auth.freshMembershipIDs()
                guard let membership = auth.memberships.first(where: { $0.slug == legacy.slug }), !legacy.staffInbox || auth.staffToolsAvailable else {
                    throw APIError(status: 403, code: "link_membership_unavailable", detail: String(localized: "This update isn't available to your account."))
                }
                return MobileLink(makerspaceID: membership.id, destination: legacy.staffInbox ? .inbox : .home)
            }, owner: routingOwner)
            Task { await linkRouter.process() }
        } else { linkRouter.unbind(owner: routingOwner) }
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
                Text("Choose a new password").brandFont(.largeTitle, weight: .bold)
                Text("Replace your temporary password to continue.").foregroundStyle(Color.swMuted)
                PasswordControl(title: String(localized: "Current password"), text: $current, identifier: "current-password")
                PasswordControl(title: String(localized: "New password"), text: $new, newPassword: true, identifier: "new-password")
                PasswordControl(title: String(localized: "Confirm password"), text: $confirmation, newPassword: true, identifier: "confirm-password")
                if let error = auth.error { SWError(message: error) }
                Button(auth.busy ? "Updating…" : "Update password") {
                    Task { await auth.changePassword(current: current, new: new, confirmation: confirmation); current = ""; new = ""; confirmation = "" }
                }.buttonStyle(SWPrimary()).disabled(auth.busy)
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 48).disabled(auth.busy)
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg).onDisappear { current = ""; new = ""; confirmation = "" }
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
        configuration.label.brandFont(.headline).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 16)
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
                        Text("Welcome back.").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                        Text("Sign in to your makerspace account.").foregroundStyle(Color.swMuted)
                        SWCard {
                            Text("Sign in").brandFont(.title2, weight: .bold)
                            if auth.configuration == nil {
                                Text("Couldn't load sign-in options. Try again.").foregroundStyle(Color.swMuted)
                                if let error = auth.error { SWError(message: error) }
                                Button("Try again") { Task { await auth.retryRestore() } }.buttonStyle(SWPrimary())
                            } else if !auth.passwordEnabled {
                                Text("Sign-in isn't available here").brandFont(.headline)
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
                                if typeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("New here?").foregroundStyle(Color.swMuted)
                                        Button("Create account") { accountForm = auth.accountForm(.signUp) }
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .accessibilityIdentifier("create-account")
                                    }
                                } else {
                                    HStack { Text("New here?").foregroundStyle(Color.swMuted); Button("Create account") { accountForm = auth.accountForm(.signUp) }.frame(minHeight: 48).accessibilityIdentifier("create-account") }
                                }
                            }
                            }
                        }.disabled(auth.busy)
                        if !state.locked { Button("Change server") { state.changeServer() }.frame(minHeight: 48).disabled(auth.busy) }
                    }.frame(maxWidth: 460)
                    if geometry.size.width >= 960 && geometry.size.height >= 600 && !typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 24) {
                            BrandWordmark(spacious: true)
                            Text("Less searching.\nMore making.").font(.custom("Unbounded-Regular", size: 24, relativeTo: .title2).weight(.medium))
                            Text("Borrow hardware. Make room for your next idea.").brandFont(.title3)
                        }.padding(40).frame(maxWidth: 460, minHeight: 460, alignment: .leading)
                            .background(Color.swSurface, in: RoundedRectangle(cornerRadius: 28)).foregroundStyle(Color.swInk)
                            .accessibilityHidden(true)
                    }
                }.padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("sign-in-scroll")
        }
        .sheet(item: $accountForm) { form in AccountAccessView(form: form) { auth.username = form.email; accountForm = nil } }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brandFont(.headline)
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
        let compactLayout = compact || verticalSize == .compact || typeSize.isAccessibilitySize
        let originalBrand = Brand.appName == "Space Works"
        let useSymbol = Brand.hasCustomWordmark ? (compactLayout ? Brand.hasCustomSymbol : !Brand.hasCustomStacked) : compactLayout
        if originalBrand || Brand.hasCustomWordmark {
            if useSymbol {
                Image("BrandSymbol").resizable().scaledToFit().frame(width: 52, height: 48)
                    .padding(12).accessibilityLabel(Text(verbatim: Brand.appName))
            } else {
                Image("BrandStacked").resizable().scaledToFit().frame(width: spacious ? 280 : 180, height: spacious ? 100 : 64)
                    .padding(16).accessibilityLabel(Text(verbatim: Brand.appName))
            }
        } else { Text(verbatim: Brand.appName).brandFont(.headline).foregroundStyle(Color.swAccentInk) }
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
                    Text("Save your recovery codes").brandFont(.largeTitle, weight: .bold)
                    Text("Keep these somewhere safe. Each code works once.").foregroundStyle(Color.swMuted)
                    ForEach(auth.recoveryCodes, id: \.self) { Text($0).monospacedDigit().textSelection(.enabled) }
                    Toggle("I've saved my recovery codes", isOn: $codesSaved).frame(minHeight: 48)
                    Button("Continue") { auth.confirmRecoveryCodes() }.buttonStyle(SWPrimary()).disabled(!codesSaved)
                } else {
                    Text(auth.mfa?.enrollment_required == true ? "Add extra security" : "Check your authenticator").brandFont(.largeTitle, weight: .bold)
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
                    Text(recoveryEntry ? "Recovery code" : "Authentication code").brandFont(.headline)
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
    var label = String(localized: "Authenticator setup QR code")
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
    var account: AccountState? = nil
    @State private var emailForm: AccountAccessState?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a makerspace").brandFont(.largeTitle, weight: .bold)
                if auth.memberships.isEmpty {
                    Text("You haven’t joined a makerspace yet.").foregroundStyle(Color.swMuted)
                }
                ForEach(auth.memberships, id: \.id) { membership in
                    Button { Task { await auth.select(membership.id) } } label: {
                        SWCard {
                            Text(membership.slug).brandFont(.title2, weight: .bold)
                            Text(membership.role_name).foregroundStyle(Color.swMuted)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("makerspace-\(membership.id)")
                }
                if let account {
                    NavigationLink("Account and security") { AccountView(state: account, privacyURL: Brand.privacyURL.flatMap(URL.init(string:)), supportURL: Brand.supportURL.flatMap(URL.init(string:))) }
                        .frame(minHeight: 48).accessibilityIdentifier("account-entry")
                }
                if auth.user?.email_verified == false { Button("Confirm email") { emailForm = auth.accountForm(.emailVerification) }.frame(minHeight: 48) }
                if let error = auth.error { SWError(message: error) }
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 48).disabled(auth.busy)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg)
            .sheet(item: $emailForm) { form in AccountAccessView(form: form) { emailForm = nil } }
    }
}
