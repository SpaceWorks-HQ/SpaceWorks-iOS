#if DEBUG
import SwiftUI
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class DemoSession {
    enum Role: String, CaseIterable { case member = "Member", staff = "Staff" }
    enum Scenario: String, CaseIterable {
        case password = "Password", mfa = "MFA", enrollment = "Enrollment", expired = "Expired challenge"
        case offline = "Offline", throttled = "Too many requests", superadmin = "Superadmin", updateRequired = "Update required"
    }
    enum Stage: Equatable { case welcome, signIn, mfa, recovery, makerspace, shell, webConsole, updateRequired }
    var role = Role.member
    var scenario = Scenario.password
    var stage = Stage.welcome
    var username = ""
    var password = ""
    var code = ""
    var error: String?
    var retryAfter: Date?
    var selectedSpace = 0
    var actionScenario = DemoMemberActionsRepository.Scenario.success
    var profileDisplayName: String?
    var memberScenario = DemoMemberRepository.Scenario.populated
    let spaces = ["Fab Lab Kochi", "Maker Space Bengaluru"]
    var name: String { profileDisplayName ?? (role == .member ? "Meera Nair" : "Arjun Rao") }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            if arguments.contains("--demo-empty") { memberScenario = .empty }
            if arguments.contains("--demo-error") { memberScenario = .offline }
            if arguments.contains("--demo-revoked") { memberScenario = .revokedCard }
            if arguments.contains("--demo-action-pending") { actionScenario = .pending }
            if arguments.contains("--demo-action-waitlisted") { actionScenario = .waitlisted }
            if arguments.contains("--demo-action-conflict") { actionScenario = .conflict }
            if arguments.contains("--demo-action-refused") { actionScenario = .refused }
            if arguments.contains("--demo-action-throttled") { actionScenario = .throttled }
        }
    }
    func signIn() {
        guard !username.isEmpty, !password.isEmpty else { error = "Enter your email or username and password."; return }
        guard (retryAfter ?? .distantPast) <= Date() else { return }
        error = nil; password = ""
        switch scenario {
        case .offline: error = "Couldn't connect. Try again."
        case .throttled: error = "Too many requests. Try again later."; retryAfter = Date().addingTimeInterval(10)
        case .expired: error = "Your sign-in expired. Try again."
        case .superadmin: stage = .webConsole
        case .updateRequired: stage = .updateRequired
        case .password: stage = .makerspace
        case .mfa, .enrollment: stage = .mfa
        }
    }
    func verify() {
        guard code == "123456" || code == "sample-recovery" else { error = "That code didn’t work. Try again."; return }
        code = ""; error = nil; stage = scenario == .enrollment ? .recovery : .makerspace
    }
    func acceptDemoProvider() { error = nil; stage = scenario == .enrollment || scenario == .mfa ? .mfa : .makerspace }
    func reset() { username = ""; password = ""; code = ""; error = nil; retryAfter = nil; selectedSpace = 0; profileDisplayName = nil; actionScenario = .success; stage = .welcome }
}

enum DemoProvider: String, CaseIterable, Identifiable {
    case google = "Google", apple = "Apple", organization = "your organization", phone = "phone"
    var id: Self { self }
}

struct DemoRoot: View {
    let exit: () -> Void
    @State private var session = DemoSession()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Demo mode · sample data").font(.caption.bold())
                Spacer()
                Button("Exit demo") { session.reset(); exit() }.frame(minHeight: 48)
            }.padding(.horizontal, 20).foregroundStyle(Color.swOnEmphasis).background(Color.swEmphasis)
            if session.stage == .shell {
                DemoShell(session: session).id("\(session.role.rawValue).\(session.selectedSpace).\(session.memberScenario.rawValue)")
            }
            else { DemoAuthView(session: session) }
        }.background(Color.swBg)
    }
}

struct DemoAuthView: View {
    @Bindable var session: DemoSession
    @State private var passwordFocused = false
    @State private var provider: DemoProvider?
    @State private var accountForm: AccountAccessState?
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
                        Picker("App data preview", selection: $session.memberScenario) { ForEach(DemoMemberRepository.Scenario.allCases, id: \.self) { Text($0.rawValue) } }
                        Button("Continue as \(session.role.rawValue.lowercased())") { session.stage = .signIn }.buttonStyle(SWPrimary())
                    case .signIn:
                        Text("Welcome back.").font(.largeTitle.bold())
                        Text("Your makerspace, in your pocket.").foregroundStyle(Color.swMuted)
                        GeometryReader { geometry in
                            GoogleProviderButton(wide: geometry.size.width >= 312) { provider = .google }
                        }.frame(height: 48)
                        AppleProviderButton { provider = .apple }.frame(height: 48)
                        ForEach(DemoProvider.allCases.filter { $0 == .organization || ($0 == .phone && session.role == .member) }) { choice in
                            Button("Continue with \(choice.rawValue)") { provider = choice }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
                        }
                        Text("or with your email").font(.caption).foregroundStyle(Color.swMuted)
                        Text("Email or username").font(.headline)
                        TextField("Email or username", text: $session.username, prompt: Text("Email or username").foregroundColor(Color.swMuted)).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().submitLabel(.next).onSubmit { passwordFocused = true }
                            .demoField().accessibilityIdentifier("demo-username")
                        PasswordControl(title: "Password", text: $session.password, identifier: "demo-password", focus: $passwordFocused)
                        Text("Use any email and password in this demo.").font(.caption).foregroundStyle(Color.swMuted)
                        if let error = session.error { SWError(message: error) }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button("Sign in") { session.signIn() }.buttonStyle(SWPrimary()).accessibilityIdentifier("demo-sign-in")
                                .disabled((session.retryAfter ?? .distantPast) > context.date)
                        }
                        Button("Forgot password?") { accountForm = demoAccountForm(.requestReset) }.frame(minHeight: 48)
                        Button("Create account") { accountForm = demoAccountForm(.signUp) }.frame(minHeight: 48)
                        Button("Back") { session.reset() }.frame(minHeight: 48)
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
                        Button("Back to sign in") { session.stage = .signIn; session.error = nil }.frame(minHeight: 48)
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
                    case .webConsole:
                        Text("Use the web console").font(.largeTitle.bold())
                        Text("Superadmin accounts cannot sign in on a phone or tablet.").foregroundStyle(Color.swMuted)
                        Button("Back to demo") { session.reset() }.buttonStyle(SWPrimary())
                    case .updateRequired:
                        Text("Update required").font(.largeTitle.bold())
                        Text("Update the app to keep using this server. This is a preview of the server's minimum-version gate.").foregroundStyle(Color.swMuted)
                        Button("Back to demo") { session.reset() }.buttonStyle(SWPrimary())
                    case .shell: EmptyView()
                    }
                }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
            .sheet(item: $provider) { DemoProviderView(session: session, provider: $0) }
            .sheet(item: $accountForm) { form in AccountAccessView(form: form) { session.username = form.email; accountForm = nil } }
    }
    private func demoAccountForm(_ step: AccountAccessState.Step) -> AccountAccessState {
        AccountAccessState(step: step, isDemo: true, create: { _, _, _, _ in }, request: { _ in }, reset: { _, code, _ in
            if code != "123456" { throw NSError(domain: "DemoReset", code: 1) }
        })
    }
}
struct DemoProviderView: View {
    let session: DemoSession
    let provider: DemoProvider
    @Environment(\.dismiss) private var dismiss
    @State private var state = DemoProviderState()
    var body: some View {
        NavigationStack {
            ScrollView {
                SWCard {
                    Text("Continue with \(provider.rawValue)").font(.largeTitle.bold())
                    Text("Demo mode. No provider account is connected and no message is sent.").foregroundStyle(Color.swMuted)
                    if provider == .phone {
                        if state.step == .phone {
                            Text("We'll send a verification code.").foregroundStyle(Color.swMuted)
                            Picker("Country code", selection: $state.country) { Text("India +91").tag("+91"); Text("United States +1").tag("+1"); Text("United Kingdom +44").tag("+44") }.frame(minHeight: 48)
                            Text("Phone number").font(.headline)
                            TextField("Phone number", text: $state.phone).textContentType(.telephoneNumber).keyboardType(.phonePad).demoField()
                            Button("Send verification code") { state.sendCode() }.buttonStyle(SWPrimary())
                                .disabled(state.resendAfter > Date())
                        } else {
                            Text("Enter your verification code").font(.title2.bold())
                            Text(state.country + " " + state.phone).foregroundStyle(Color.swMuted)
                            TextField("Verification code", text: $state.code).textContentType(.oneTimeCode).demoField()
                            Text("Use 123456 in this demo. No message was sent.").font(.caption).foregroundStyle(Color.swMuted)
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                Button(tick.date < state.resendAfter ? "Resend in \(max(1, Int(ceil(state.resendAfter.timeIntervalSince(tick.date)))))s" : "Send another code") { state.sendCode() }
                                    .frame(minHeight: 48).disabled(tick.date < state.resendAfter)
                            }
                            Button("Change number") { state.changeNumber() }.frame(minHeight: 48)
                        }
                    } else {
                        Label(session.name, systemImage: "person.crop.circle").font(.title2)
                    }
                    Picker("Preview result", selection: $state.outcome) { ForEach(DemoProviderState.Outcome.allCases, id: \.self) { Text($0.rawValue) } }
                    if let error = state.error { SWError(message: error) }
                    if provider != .phone || state.step == .code {
                        Button(provider == .phone ? "Verify" : "Continue demo account") {
                            if state.complete(phone: provider == .phone) { session.acceptDemoProvider(); dismiss() }
                        }.buttonStyle(SWPrimary())
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Color.swBg).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48) } }
        }
    }
}

struct DemoShell: View {
    let session: DemoSession
    @State private var member: MemberState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigation = MemberNavigation()
    @State private var cart: RequestCartState
    @State private var drafts: MemberActionDrafts
    @State private var capabilities: MemberCapabilities
    @State private var actions: DemoMemberActionsRepository
    @State private var columns = NavigationSplitViewVisibility.automatic
    init(session: DemoSession) {
        self.session = session
        let store = DemoMemberStore()
        let actions = DemoMemberActionsRepository(store: store, scenario: session.actionScenario, name: session.name)
        _actions = State(initialValue: actions)
        _cart = State(initialValue: RequestCartState(repository: actions))
        _drafts = State(initialValue: MemberActionDrafts(repository: actions))
        _capabilities = State(initialValue: MemberCapabilities(repository: actions, makerspaceID: 7))
        _member = State(initialValue: MemberState(repository: DemoMemberRepository(scenario: session.memberScenario, name: session.name, store: store)))
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $columns) {
                List(AppTab.allCases) { tab in
                    Button(tab.rawValue) {
                        navigation.selected = tab
                        columns = geometry.size.width >= 1000 ? .all : .detailOnly
                    }.frame(minHeight: 48).accessibilityIdentifier("nav-\(tab.rawValue)")
                        .listRowBackground(navigation.selected == tab ? Color.swSidebarActive : Color.swSidebar)
                        .foregroundStyle(navigation.selected == tab ? Color.swOnAccent : Color.swInk)
                }.scrollContentBackground(.hidden).background(Color.swSidebar).navigationTitle(Brand.appName)
            } detail: { destination(navigation.selected) }
        } else {
            TabView(selection: $navigation.selected) {
                ForEach(AppTab.allCases) { tab in
                    destination(tab)
                        .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }.tag(tab)
                        .badge(tab == .inbox ? member.unreadCount ?? 0 : 0)
                }
            }
        }
        }.onChange(of: navigation.selected) { _, _ in
            columns = geometry.size.width >= 1000 ? .all : .detailOnly
        }.onChange(of: geometry.size.width, initial: true) { _, width in
            columns = width >= 1000 ? .all : .detailOnly
        }
        }.task { async let config: Void = capabilities.load(); await member.loadUnreadCount(); await config }.onDisappear { member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate() }
        .onChange(of: session.actionScenario) { _, scenario in Task { await actions.preview(scenario) } }
        .onChange(of: sizeClass) { _, value in if value == .compact { navigation.compactInventory() } }
    }
    private func destination(_ tab: AppTab) -> some View {
        NavigationStack(path: navigation.path(tab)) {
            DemoDestination(session: session, member: member, tab: tab, actions: actions, cart: cart, navigation: navigation, capabilities: capabilities, drafts: drafts)
                .navigationDestination(for: MemberRoute.self) { route in
                    MemberRouteView(route: route, member: member, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities, isDemo: true) {
                        if let profile = try? await actions.profile() { session.profileDisplayName = profile.display_name }
                    }
                }
        }
    }
}
struct DemoDestination: View {
    let session: DemoSession
    let member: MemberState
    let tab: AppTab
    let actions: DemoMemberActionsRepository
    let cart: RequestCartState
    let navigation: MemberNavigation
    let capabilities: MemberCapabilities
    let drafts: MemberActionDrafts
    var body: some View {
        Group {
        if tab != .profile { MemberContent(state: member, tab: tab, name: session.name, selectTab: { navigation.selected = $0 }, actions: actions, cart: cart, navigation: navigation, drafts: drafts) }
        else { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome back, \(session.name).").font(.largeTitle.bold())
                Text(session.spaces[session.selectedSpace]).foregroundStyle(Color.swMuted)
                SWCard {
                        Text(session.role.rawValue).font(.headline)
                        if capabilities.busy { ProgressView("Loading account options…") }
                        if let error = capabilities.error { SWError(message: error); Button("Retry account options") { Task { await capabilities.load() } }.frame(minHeight: 48) }
                        if capabilities.selfService { NavigationLink("Edit profile", value: MemberRoute.contact).frame(minHeight: 48) }
                        if capabilities.preferences { NavigationLink("Communication preferences", value: MemberRoute.preferences).frame(minHeight: 48) }
                        Picker("Action preview result", selection: Binding(get: { session.actionScenario }, set: { session.actionScenario = $0 })) {
                            ForEach(DemoMemberActionsRepository.Scenario.allCases, id: \.self) { Text($0.rawValue) }
                        }.frame(minHeight: 48).accessibilityIdentifier("action-preview-result")
                        Button("Show helpful tips") { member.replayGuidance() }.frame(minHeight: 48)
                        Button("Sign out") { session.reset() }.frame(minHeight: 48)
                }
            }.padding(24).frame(maxWidth: 960).frame(maxWidth: .infinity)
        } }
        }.background(Color.swBg).navigationTitle(tab.rawValue)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(session.spaces.indices, id: \.self) { index in Button(session.spaces[index]) { session.selectedSpace = index } }
                    } label: { Label(session.spaces[session.selectedSpace], systemImage: "building.2") }
                }
            }
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
