#if DEBUG
import SwiftUI
import Observation

@MainActor @Observable
final class DemoSession {
    enum Role: String, CaseIterable { case member = "Member", staff = "Staff" }
    enum Scenario: String, CaseIterable { case password = "Password", mfa = "MFA", enrollment = "Enrollment" }
    enum Stage: Equatable { case welcome, signIn, mfa, recovery, makerspace, shell }
    var role = Role.member
    var scenario = Scenario.password
    var stage = Stage.welcome
    var username = ""
    var password = ""
    var code = ""
    var error: String?
    var selectedSpace = 0
    let spaces = ["Fab Lab Kochi", "Maker Space Bengaluru"]
    var name: String { role == .member ? "Meera Nair" : "Arjun Rao" }
    func signIn() {
        guard !username.isEmpty, !password.isEmpty else { error = "Enter your email or username and password."; return }
        error = nil; password = ""; stage = scenario == .password ? .makerspace : .mfa
    }
    func verify() {
        guard code == "123456" || code == "sample-recovery" else { error = "That code didn’t work. Try again."; return }
        code = ""; error = nil; stage = scenario == .enrollment ? .recovery : .makerspace
    }
    func reset() { username = ""; password = ""; code = ""; error = nil; selectedSpace = 0; stage = .welcome }
}

struct DemoRoot: View {
    let exit: () -> Void
    @State private var session = DemoSession()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Demo mode · sample data").font(.caption.bold())
                Spacer()
                Button("Exit demo") { session.reset(); exit() }.frame(minHeight: 44)
            }.padding(.horizontal, 20).foregroundStyle(Color.swOnEmphasis).background(Color.swEmphasis)
            if session.stage == .shell { DemoShell(session: session) }
            else { DemoAuthView(session: session) }
        }.background(Color.swBg)
    }
}

struct DemoAuthView: View {
    @Bindable var session: DemoSession
    @FocusState private var passwordFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandWordmark()
                SWCard {
                    switch session.stage {
                    case .welcome:
                        Text("Make yourself at home.").font(.largeTitle.bold())
                        Text("Explore sample makerspaces and complete app flows. Nothing is sent to a server.").foregroundStyle(Color.swMuted)
                        Picker("Demo role", selection: $session.role) { ForEach(DemoSession.Role.allCases, id: \.self) { Text($0.rawValue) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("demo-role")
                        Picker("Sign-in preview", selection: $session.scenario) { ForEach(DemoSession.Scenario.allCases, id: \.self) { Text($0.rawValue) } }
                        Button("Continue as \(session.role.rawValue.lowercased())") { session.stage = .signIn }.buttonStyle(SWPrimary())
                    case .signIn:
                        Text("Welcome back.").font(.largeTitle.bold())
                        Text("Your makerspace, in your pocket.").foregroundStyle(Color.swMuted)
                        Text("Email or username").font(.headline)
                        TextField("Email or username", text: $session.username).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().demoField().accessibilityIdentifier("demo-username")
                        Text("Password").font(.headline)
                        SecureField("Password", text: $session.password).focused($passwordFocused)
                            .submitLabel(.done).onSubmit { passwordFocused = false }
                            .demoField().accessibilityIdentifier("demo-password")
                        Text("Use any email and password in this demo.").font(.caption).foregroundStyle(Color.swMuted)
                        if let error = session.error { SWError(message: error) }
                        Button("Sign in") { session.signIn() }.buttonStyle(SWPrimary()).accessibilityIdentifier("demo-sign-in")
                        Button("Back") { session.reset() }.frame(minHeight: 44)
                    case .mfa:
                        Text(session.scenario == .enrollment ? "Set up two-step sign-in" : "Verify your sign-in").font(.largeTitle.bold())
                        if session.scenario == .enrollment {
                            QRCodeView(value: "otpauth://totp/SpaceWorks:demo?secret=JBSWY3DPEHPK3PXP&issuer=SpaceWorks")
                            Text("Can't scan? Enter this key").font(.headline)
                            Text("JBSWY3DPEHPK3PXP").font(.body.monospaced()).textSelection(.enabled)
                        }
                        Text("Authenticator or recovery code").font(.headline)
                        TextField("Authenticator or recovery code", text: $session.code).demoField()
                            .textContentType(.oneTimeCode).accessibilityIdentifier("demo-mfa-code")
                        Text("Use 123456 or sample-recovery in this demo.").font(.caption).foregroundStyle(Color.swMuted)
                        if let error = session.error { SWError(message: error) }
                        Button("Verify") { session.verify() }.buttonStyle(SWPrimary())
                        Button("Back to sign in") { session.stage = .signIn; session.error = nil }.frame(minHeight: 44)
                    case .recovery:
                        Text("Save your recovery codes").font(.largeTitle.bold())
                        Text("Sample codes for this demo. Real codes appear once after enrollment.").foregroundStyle(Color.swMuted)
                        Text("sample-recovery\nsample-backup").font(.body.monospaced()).textSelection(.enabled)
                        Button("I saved my codes. Continue") { session.stage = .makerspace }.buttonStyle(SWPrimary())
                    case .makerspace:
                        Text("Choose a makerspace").font(.largeTitle.bold())
                        ForEach(session.spaces.indices, id: \.self) { index in
                            Button { session.selectedSpace = index; session.stage = .shell } label: {
                                Label(session.spaces[index], systemImage: "building.2").frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityIdentifier("demo-space-\(index)")
                        }
                    case .shell: EmptyView()
                    }
                }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
    }
}

struct DemoShell: View {
    let session: DemoSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected = AppTab.home
    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(AppTab.allCases) { tab in
                    Button(tab.rawValue) { selected = tab }.frame(minHeight: 44).accessibilityIdentifier("nav-\(tab.rawValue)")
                        .listRowBackground(selected == tab ? Color.swSidebarActive : Color.swSidebar)
                        .foregroundStyle(selected == tab ? Color.swOnAccent : Color.swInk)
                }.scrollContentBackground(.hidden).background(Color.swSidebar).navigationTitle(Brand.appName)
            } detail: { NavigationStack { DemoDestination(session: session, tab: selected) } }
        } else {
            TabView(selection: $selected) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack { DemoDestination(session: session, tab: tab) }
                        .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }.tag(tab)
                }
            }
        }
    }
}
struct DemoDestination: View {
    let session: DemoSession
    let tab: AppTab
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome back, \(session.name).").font(.largeTitle.bold())
                Text(session.spaces[session.selectedSpace]).foregroundStyle(Color.swMuted)
                SWCard {
                    if tab == .profile {
                        Text(session.role.rawValue).font(.headline)
                        Button("Sign out") { session.reset() }.frame(minHeight: 44)
                    } else { Text("Nothing here yet.") }
                }
            }.padding(24).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle(tab.rawValue)
    }
}
private extension View {
    func demoField() -> some View {
        padding(14).frame(minHeight: 48).foregroundStyle(Color.swInk)
            .background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
    }
}
#endif
