import SwiftUI
import SpaceWorksAPI
import CoreImage.CIFilterBuiltins

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
                Text("Update your temporary password before opening your makerspace.").foregroundStyle(Color.swMuted)
                Text("Current password").font(.headline)
                SecureField("Current password", text: $current).textContentType(.password).padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                Text("New password").font(.headline)
                SecureField("New password", text: $new).textContentType(.newPassword).padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                Text("Confirm new password").font(.headline)
                SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword).padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                if let error = auth.error { SWError(message: error) }
                Button(auth.busy ? "Updating…" : "Update password") {
                    Task { await auth.changePassword(current: current, new: new, confirmation: confirmation); current = ""; new = ""; confirmation = "" }
                }.buttonStyle(SWPrimary()).disabled(auth.busy)
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 44).disabled(auth.busy)
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
        Label(message, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(Color.swDanger).accessibilityIdentifier("auth-error")
            .accessibilityAddTraits(.updatesFrequently)
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
    @FocusState private var passwordFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .center, spacing: 40) {
                    VStack(alignment: .leading, spacing: 24) {
                        BrandWordmark()
                        Text("Welcome back.").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Your makerspace, in your pocket.").foregroundStyle(Color.swMuted)
                        SWCard {
                            Text("Sign in").font(.title2.bold())
                            if !auth.passwordEnabled {
                                Text("This deployment signs in through an identity provider. Ask your makerspace to enable native sign-in.")
                                    .foregroundStyle(Color.swMuted)
                            } else {
                            field("Email or username") {
                                TextField("Email or username", text: $auth.username).textContentType(.username)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .submitLabel(.next).onSubmit { passwordFocused = true }.accessibilityIdentifier("username")
                            }
                            field("Password") {
                                HStack {
                                    Group {
                                        if showPassword { TextField("Password", text: $auth.password) }
                                        else { SecureField("Password", text: $auth.password) }
                                    }.textContentType(.password).focused($passwordFocused).submitLabel(.done)
                                        .onSubmit { passwordFocused = false }.accessibilityIdentifier("password")
                                    Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                                        .accessibilityLabel(showPassword ? "Hide password" : "Show password").frame(minWidth: 44, minHeight: 44)
                                }
                            }
                            if let error = auth.error { SWError(message: error) }
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Button(auth.busy ? "Signing in…" : "Sign in") { Task { await auth.signIn() } }
                                    .buttonStyle(SWPrimary()).disabled(auth.busy || (auth.retryAfter ?? .distantPast) > context.date)
                                    .accessibilityIdentifier("sign-in")
                            }
                            }
                        }.disabled(auth.busy)
                        if !state.locked { Button("Change server") { state.changeServer() }.frame(minHeight: 44).disabled(auth.busy) }
                    }.frame(maxWidth: 460)
                    if geometry.size.width >= 900 && !typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 24) {
                            Image(systemName: "wrench.and.screwdriver").font(.system(size: 64)).foregroundStyle(Color.swInk)
                            Text("Less searching.\nMore making.").font(.largeTitle.bold())
                            Text("Borrow hardware. Make room for your next idea.").font(.title3)
                        }.padding(40).frame(maxWidth: 460, minHeight: 460, alignment: .leading)
                            .background(Color.swSuccess, in: RoundedRectangle(cornerRadius: 28)).foregroundStyle(Color.swOnSuccess)
                            .accessibilityHidden(true)
                    }
                }.padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
        }
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
    var body: some View {
        if Brand.appName == "Space Works" {
            Image("Wordmark").resizable().scaledToFit().frame(maxWidth: 180, maxHeight: 64)
                .padding(.vertical, 16).accessibilityLabel("Space Works")
        } else { Text(Brand.appName).font(.headline).foregroundStyle(Color.swAccentInk) }
    }
}

struct MFAView: View {
    @Bindable var auth: AuthState
    var body: some View {
        ScrollView {
            SWCard {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                if auth.stage == .recoveryCodes {
                    Text("Save your recovery codes").font(.largeTitle.bold())
                    Text("Keep these somewhere safe. Each code works once.").foregroundStyle(Color.swMuted)
                    ForEach(auth.recoveryCodes, id: \.self) { Text($0).font(.body.monospaced()).textSelection(.enabled) }
                    Button("I saved my codes. Continue") { auth.confirmRecoveryCodes() }.buttonStyle(SWPrimary())
                } else {
                    Text(auth.mfa?.enrollment_required == true ? "Set up two-step sign-in" : "Verify your sign-in").font(.largeTitle.bold())
                    if let enrollment = auth.enrollment {
                        Text("Add this account to your authenticator app.").foregroundStyle(Color.swMuted)
                        QRCodeView(value: enrollment.provisioning_uri)
                        Text("Can't scan? Enter this key").font(.headline)
                        Text(enrollment.secret).font(.body.monospaced()).textSelection(.enabled)
                    }
                    Text("Authenticator or recovery code").font(.headline)
                    TextField("Authenticator or recovery code", text: $auth.code).textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().padding(16)
                        .background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("mfa-code")
                    if let error = auth.error { SWError(message: error) }
                    Button(auth.busy ? "Verifying…" : "Verify") { Task { await auth.verify() } }
                        .buttonStyle(SWPrimary()).disabled(auth.busy).accessibilityIdentifier("verify")
                    Button("Back to sign in") { auth.backToSignIn() }.frame(minHeight: 44).disabled(auth.busy)
                }
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}
struct QRCodeView: View {
    let value: String
    var body: some View {
        if let image = image {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 240)
                .accessibilityLabel("Authenticator setup QR code")
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
                Button("Sign out") { Task { await auth.signOut() } }.frame(minHeight: 44)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg)
    }
}
