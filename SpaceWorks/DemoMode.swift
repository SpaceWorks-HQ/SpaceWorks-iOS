#if DEBUG
import SwiftUI
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class DemoSession {
    enum Role: String, CaseIterable { case member = "Member", staff = "Staff" }
    enum Scenario: String, CaseIterable {
        case password = "Password", mfa = "MFA", enrollment = "Enrollment", expired = "Expired challenge"
        case noMemberships = "No makerspaces", offline = "Offline", throttled = "Too many requests", superadmin = "Superadmin", updateRequired = "Update required"
    }
    enum Stage: Equatable { case welcome, signIn, mfa, recovery, makerspace, shell, webConsole, updateRequired, noMakerspaces, securityCompletion, emailVerification }
    var role = Role.member
    var scenario = Scenario.password
    var stage = Stage.welcome
    var username = ""
    var password = ""
    var code = ""
    var error: String?
    var retryAfter: Date?
    var selectedSpace = 0
    var availableSpaces: Set<Int> = [0, 1]
    var accountScenario = DemoAccountScenario.populated
    var accountCooldown = AccountAccessCooldown()
    var emailCooldown = AccountAccessCooldown()
    var demoEmailConfirmed = false
    var emailFlowID = UUID()
    var securityEnrollment = false
    var securityCodes: [String] = []
    var securityMessage: String?
    var fixNotice: String?
    var pendingAccountFix: DemoDeletionState.Blocker?
    @ObservationIgnored var globalAccountRepository: DemoAccountRepository?
    @ObservationIgnored var memberAccountRepositories: [Int: DemoAccountRepository] = [:]
    @ObservationIgnored var guidanceFlags: [DemoGuidanceKey: Bool] = [:]
    @ObservationIgnored var guidanceEpoch = UUID()
    var notificationState = DemoNotificationState()
    @ObservationIgnored private var paymentRepositories: [Int: DemoPaymentRepository] = [:]
    var staffScenario = DemoStaffScenario.populated
    var actionScenario = DemoMemberActionsRepository.Scenario.success
    var profileDisplayName: String?
    var memberScenario = DemoMemberRepository.Scenario.populated
    let spaces = ["Fab Lab Kochi", "Maker Space Bengaluru"]
    var membershipStage: Stage { availableSpaces.isEmpty ? .noMakerspaces : .makerspace }
    var name: String { profileDisplayName ?? (role == .member ? "Meera Nair" : "Arjun Rao") }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            if arguments.contains("--demo-no-memberships") { scenario = .noMemberships }
            if arguments.contains("--demo-account-no-mfa") { accountScenario = .noMFA }
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
        guard !username.isEmpty, !password.isEmpty else { error = String(localized: "Enter your email or username and password."); return }
        guard (retryAfter ?? .distantPast) <= Date() else { return }
        error = nil; password = ""
        if scenario == .password, username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "unverified", !demoEmailConfirmed {
            emailFlowID = UUID(); stage = .emailVerification; return
        }
        switch scenario {
        case .offline: error = String(localized: "Couldn't connect. Try again.")
        case .throttled: error = String(localized: "Too many requests. Try again later."); retryAfter = Date().addingTimeInterval(10)
        case .expired: error = String(localized: "Your sign-in expired. Try again.")
        case .superadmin: stage = .webConsole
        case .updateRequired: stage = .updateRequired
        case .noMemberships: availableSpaces = []; stage = .noMakerspaces
        case .password: stage = membershipStage
        case .mfa, .enrollment: stage = .mfa
        }
    }
    func verify() {
        guard code == "123456" || code == "sample-recovery" else { error = String(localized: "That code didn’t work. Try again."); return }
        code = ""; error = nil; stage = scenario == .enrollment ? .recovery : membershipStage
    }
    func acceptDemoProvider() { error = nil; if scenario == .noMemberships { availableSpaces = []; stage = .noMakerspaces } else { stage = scenario == .enrollment || scenario == .mfa ? .mfa : membershipStage } }
    func paymentRepository(for makerspaceID: Int) -> DemoPaymentRepository {
        if let repository = paymentRepositories[makerspaceID] { return repository }
        let repository = DemoPaymentRepository(); paymentRepositories[makerspaceID] = repository; return repository
    }
    func reset() { guidanceFlags = [:]; guidanceEpoch = UUID(); accountCooldown = AccountAccessCooldown(); emailCooldown = AccountAccessCooldown(); demoEmailConfirmed = false; emailFlowID = UUID(); fixNotice = nil; availableSpaces = [0, 1]; globalAccountRepository = nil; memberAccountRepositories = [:]; securityEnrollment = false; securityCodes = []; securityMessage = nil; pendingAccountFix = nil; paymentRepositories = [:]; notificationState = DemoNotificationState(); username = ""; password = ""; code = ""; error = nil; retryAfter = nil; selectedSpace = 0; profileDisplayName = nil; actionScenario = .success; stage = .welcome }
}

enum DemoProvider: String, CaseIterable, Identifiable {
    case google = "Google", apple = "Apple", organization = "your organization", phone = "phone"
    var id: Self { self }
}

struct DemoRoot: View {
    let exit: () -> Void
    @State private var session = DemoSession()
    @State private var linkRouter = MobileLinkRouter()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Demo mode · sample data").brandFont(.caption, weight: .bold)
                Spacer()
                Button { session.reset(); exit() } label: {
                    Label("Exit demo", systemImage: "xmark").labelStyle(.iconOnly)
                        .font(.title3).frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
            }.padding(.horizontal, 20).foregroundStyle(Color.swOnEmphasis).background(Color.swEmphasis)
            if session.stage == .shell {
                DemoShell(session: session, linkRouter: linkRouter).id("\(session.role.rawValue).\(session.selectedSpace).\(session.memberScenario.rawValue)")
            }
            else if session.stage == .emailVerification { DemoEmailVerificationView(session: session).id(session.emailFlowID) }
            else if session.stage == .securityCompletion {
                AccountSecurityCompletionView(codes: session.securityCodes, message: session.securityMessage ?? String(localized: "Sign in again to continue."), continueToSignIn: session.finishSecurityTransition)
            } else if session.stage == .noMakerspaces { DemoAccountLandingView(session: session) }
            else { DemoAuthView(session: session) }
        }.background(Color.swBg)
            .safeAreaInset(edge: .bottom) { MobileLinkNotice(router: linkRouter) }
            .onChange(of: linkRouter.revision) { _, _ in Task { await linkRouter.process() } }
            .onChange(of: session.stage) { _, _ in bindRouting() }
            .onDisappear { linkRouter.reset() }
    }
    private func bindRouting() {
        guard session.stage == .shell else { linkRouter.unbind(); return }
        linkRouter.bind(account: "demo." + session.role.rawValue, refresh: {
            guard session.stage == .shell else { throw CancellationError() }
            return Set(session.availableSpaces.map { $0 + 7 })
        }, select: { id in
            guard session.stage == .shell, session.availableSpaces.contains(id - 7) else { throw CancellationError() }
            session.selectedSpace = id == 7 ? 0 : 1
        }, resolveLegacy: { legacy in
            guard session.stage == .shell, !legacy.staffInbox || session.role == .staff,
                  let id = ["fab-lab-kochi": 7, "maker-space-bengaluru": 8][legacy.slug], session.availableSpaces.contains(id - 7) else { throw CancellationError() }
            return MobileLink(makerspaceID: id, destination: legacy.staffInbox ? .inbox : .home)
        })
        Task { await linkRouter.process() }
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
                        Text("Make yourself at home.").brandFont(.largeTitle, weight: .bold)
                        Text("Explore sample makerspaces and complete app flows. Nothing is sent to a server.").foregroundStyle(Color.swMuted)
                        Picker("Demo role", selection: $session.role) { ForEach(DemoSession.Role.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                            .pickerStyle(.segmented).accessibilityIdentifier("demo-role")
                        Picker("Sign-in preview", selection: $session.scenario) { ForEach(DemoSession.Scenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                        Picker("Account data preview", selection: $session.accountScenario) { ForEach(DemoAccountScenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                        Picker("Staff data preview", selection: $session.staffScenario) { ForEach(DemoStaffScenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                        Picker("App data preview", selection: $session.memberScenario) { ForEach(DemoMemberRepository.Scenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                        Button("Continue as \(session.role.rawValue.lowercased())") { session.stage = .signIn }.buttonStyle(SWPrimary())
                    case .signIn:
                        Text("Welcome back.").brandFont(.largeTitle, weight: .bold)
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
                        Text("or with your email").brandFont(.caption).foregroundStyle(Color.swMuted)
                        Text("Email or username").brandFont(.headline)
                        TextField("Email or username", text: $session.username, prompt: Text("Email or username").foregroundColor(Color.swMuted)).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().submitLabel(.next).onSubmit { passwordFocused = true }
                            .demoField().accessibilityIdentifier("demo-username")
                        PasswordControl(title: String(localized: "Password"), text: $session.password, identifier: "demo-password", focus: $passwordFocused)
                        Text("Use any email and password in this demo.").brandFont(.caption).foregroundStyle(Color.swMuted)
                        Text("Use unverified to preview email confirmation.").brandFont(.caption).foregroundStyle(Color.swMuted)
                        if let error = session.error { SWError(message: error) }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Button("Sign in") { session.signIn() }.buttonStyle(SWPrimary()).accessibilityIdentifier("demo-sign-in")
                                .disabled((session.retryAfter ?? .distantPast) > context.date)
                        }
                        Button("Forgot password?") { accountForm = demoAccountForm(.requestReset) }.frame(minHeight: 48)
                        Button("Create account") { accountForm = demoAccountForm(.signUp) }.frame(minHeight: 48)
                        Button("Back") { session.reset() }.frame(minHeight: 48)
                    case .mfa:
                        Text(session.scenario == .enrollment ? "Set up two-step sign-in" : "Verify your sign-in").brandFont(.largeTitle, weight: .bold)
                        if session.scenario == .enrollment {
                            QRCodeView(value: "otpauth://totp/SpaceWorks:demo?secret=JBSWY3DPEHPK3PXP&issuer=SpaceWorks")
                            Text("Can't scan? Enter this key").brandFont(.headline)
                            Text(verbatim: "JBSWY3DPEHPK3PXP").font(.body.monospaced()).textSelection(.enabled)
                        }
                        Text("Authenticator or recovery code").brandFont(.headline)
                        TextField("Authenticator or recovery code", text: $session.code).demoField()
                            .textContentType(.oneTimeCode).accessibilityIdentifier("demo-mfa-code")
                        Text("Use 123456 or sample-recovery in this demo.").brandFont(.caption).foregroundStyle(Color.swMuted)
                        if let error = session.error { SWError(message: error) }
                        Button("Verify") { session.verify() }.buttonStyle(SWPrimary())
                        Button("Back to sign in") { session.stage = .signIn; session.error = nil }.frame(minHeight: 48)
                    case .recovery:
                        Text("Save your recovery codes").brandFont(.largeTitle, weight: .bold)
                        Text("Sample codes for this demo. Real codes appear once after enrollment.").foregroundStyle(Color.swMuted)
                        Text(verbatim: "sample-recovery\nsample-backup").font(.body.monospaced()).textSelection(.enabled)
                        Button("I saved my codes. Continue") { if session.securityEnrollment { session.securityEnded(codes: [], message: "Two-step sign-in was set up. Sign in again to continue.") } else { session.stage = session.membershipStage } }.buttonStyle(SWPrimary())
                    case .makerspace:
                        Text("Choose a makerspace").brandFont(.largeTitle, weight: .bold)
                        ForEach(session.spaces.indices.filter { session.availableSpaces.contains($0) }, id: \.self) { index in
                            Button { session.selectedSpace = index; session.stage = .shell } label: {
                                Label(session.spaces[index], systemImage: "building.2").frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            }.buttonStyle(.plain).accessibilityIdentifier("demo-space-\(index)")
                        }
                    case .webConsole:
                        Text("Use the web console").brandFont(.largeTitle, weight: .bold)
                        Text("Superadmin accounts cannot sign in on a phone or tablet.").foregroundStyle(Color.swMuted)
                        Button("Back to demo") { session.reset() }.buttonStyle(SWPrimary())
                    case .updateRequired:
                        Text("Update required").brandFont(.largeTitle, weight: .bold)
                        Text("Update the app to keep using this server. This is a preview of the server's minimum-version gate.").foregroundStyle(Color.swMuted)
                        Button("Back to demo") { session.reset() }.buttonStyle(SWPrimary())
                    case .shell, .noMakerspaces, .securityCompletion, .emailVerification: EmptyView()
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
                    Text("Continue with \(provider.rawValue)").brandFont(.largeTitle, weight: .bold)
                    Text("Demo mode. No provider account is connected and no message is sent.").foregroundStyle(Color.swMuted)
                    if provider == .phone {
                        if state.step == .phone {
                            Text("We'll send a verification code.").foregroundStyle(Color.swMuted)
                            Picker("Country code", selection: $state.country) { Text("India +91").tag("+91"); Text("United States +1").tag("+1"); Text("United Kingdom +44").tag("+44") }.frame(minHeight: 48)
                            Text("Phone number").brandFont(.headline)
                            TextField("Phone number", text: $state.phone).textContentType(.telephoneNumber).keyboardType(.phonePad).demoField()
                            Button("Send verification code") { state.sendCode() }.buttonStyle(SWPrimary())
                                .disabled(state.resendAfter > Date())
                        } else {
                            Text("Enter your verification code").brandFont(.title2, weight: .bold)
                            Text(state.country + " " + state.phone).foregroundStyle(Color.swMuted)
                            TextField("Verification code", text: $state.code).textContentType(.oneTimeCode).demoField()
                            Text("Use 123456 in this demo. No message was sent.").brandFont(.caption).foregroundStyle(Color.swMuted)
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                Button(tick.date < state.resendAfter ? "Resend in \(max(1, Int(ceil(state.resendAfter.timeIntervalSince(tick.date)))))s" : "Send another code") { state.sendCode() }
                                    .frame(minHeight: 48).disabled(tick.date < state.resendAfter)
                            }
                            Button("Change number") { state.changeNumber() }.frame(minHeight: 48)
                        }
                    } else {
                        Label(session.name, systemImage: "person.crop.circle").brandFont(.title2)
                    }
                    Picker("Preview result", selection: $state.outcome) { ForEach(DemoProviderState.Outcome.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
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
    let linkRouter: MobileLinkRouter
    @State private var member: MemberState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigation = MemberNavigation()
    @State private var cart: RequestCartState
    @State private var drafts: MemberActionDrafts
    @State private var capabilities: MemberCapabilities
    @State private var payments: PaymentsState
    @State private var staff: StaffState?
    @State private var account: AccountState
    @State private var actions: DemoMemberActionsRepository
    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    init(session: DemoSession, linkRouter: MobileLinkRouter) {
        self.session = session; self.linkRouter = linkRouter
        _account = State(initialValue: session.accountState(makerspaceID: session.selectedSpace + 7))
        _staff = State(initialValue: session.role == .staff ? StaffState(repository: DemoStaffRepository(scenario: session.staffScenario, makerspaceID: session.selectedSpace + 7), makerspaceID: session.selectedSpace + 7,
            actions: ["accept_request", "reject_request", "assign_box", "issue_request", "return_request", "upload_evidence", "issue_direct_loan", "manage_events", "manage_bookings"], features: ["loans.kit_checklist"]) : nil)
        _payments = State(initialValue: PaymentsState(repository: session.paymentRepository(for: session.selectedSpace + 7), isDemo: true, sleep: { _ in }))
        let store = DemoMemberStore()
        let actions = DemoMemberActionsRepository(store: store, scenario: session.actionScenario, name: session.name, makerspaceID: session.selectedSpace + 7)
        _actions = State(initialValue: actions)
        _cart = State(initialValue: RequestCartState(repository: actions))
        _drafts = State(initialValue: MemberActionDrafts(repository: actions))
        _capabilities = State(initialValue: MemberCapabilities(repository: actions, makerspaceID: session.selectedSpace + 7))
        _member = State(initialValue: session.makeGuidedMemberState(repository: DemoMemberRepository(scenario: session.memberScenario, name: session.name, store: store), makerspaceID: session.selectedSpace + 7))
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
        // Keep the navigation host's identity stable when a phone rotates or a tablet window resizes.
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $preferredCompactColumn) {
                List(AppTab.allCases) { tab in
                    Button(LocalizedStringKey(tab.rawValue)) {
                        navigation.selected = tab
                        preferredCompactColumn = .detail
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
                        .tabItem { Label(LocalizedStringKey(tab.rawValue), systemImage: tab.symbol) }.tag(tab)
                        .badge(tab == .inbox ? member.unreadCount ?? 0 : 0)
                }
            }
        }
        }.onChange(of: navigation.selected) { _, _ in
            preferredCompactColumn = .detail
            columns = geometry.size.width >= 1000 ? .all : .detailOnly
        }.onChange(of: geometry.size.width, initial: true) { _, width in
            columns = width >= 1000 ? .all : .detailOnly
        }
        }.task { async let config: Void = capabilities.load(); await member.loadUnreadCount(); await config }.onDisappear { member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); payments.invalidate(); staff?.invalidate(); account.invalidate() }
        .task(id: linkRouter.approved?.id) {
            if let approved = linkRouter.approved, approved.link.makerspaceID == session.selectedSpace + 7 {
                await MobileLinkDestination.open(approved, router: linkRouter, member: member, navigation: navigation, drafts: drafts, payment: { id in
                    try await PaymentsLinkDestination.open(id, state: payments, navigation: navigation) { linkRouter.isCurrent(approved) }
                })
            }
        }
        .onChange(of: capabilities.selfService, initial: true) { _, _ in account.updateCapabilities(selfService: capabilities.selfService, exports: capabilities.exports) }
        .onChange(of: capabilities.exports, initial: true) { _, _ in account.updateCapabilities(selfService: capabilities.selfService, exports: capabilities.exports) }
        .task(id: session.pendingAccountFix?.id) { await routePendingAccountFix() }
        .safeAreaInset(edge: .bottom) {
            if let message = session.fixNotice {
                HStack { Text(verbatim: message).foregroundStyle(Color.swMuted); Button("Done") { session.fixNotice = nil }.frame(minHeight: 48) }.padding(16).background(Color.swSurface)
            }
        }
        .onChange(of: session.actionScenario) { _, scenario in Task { await actions.preview(scenario) } }
        .onChange(of: sizeClass) { _, value in if value == .compact { navigation.compactInventory() } }
    }
    private func routePendingAccountFix() async {
        guard let blocker = session.pendingAccountFix, session.stage == .shell else { return }
        let maker = session.selectedSpace
        switch blocker.destination {
        case .payments: navigation.open(.payments, tab: .profile)
        case .activity: await member.loadActivity(); navigation.path(.activity).wrappedValue = []; navigation.selected = .activity
        case .bookings:
            await member.loadBookings()
            guard session.selectedSpace == maker, session.pendingAccountFix?.id == blocker.id else { return }
            if let row = member.bookings.first { navigation.open(.booking(row.public_token), tab: .activity) }
            else { navigation.selected = .activity }
        case .events:
            await member.loadActivity()
            guard session.selectedSpace == maker, session.pendingAccountFix?.id == blocker.id else { return }
            if let row = member.activity?.event_registrations?.first { navigation.open(.registration(row.registration_id), tab: .activity) }
            else { navigation.selected = .activity }
        case .staff:
            if staff != nil { navigation.open(.staff, tab: .profile) }
            else { navigation.open(.account, tab: .profile); session.fixNotice = String(localized: "Ask your makerspace to update staff responsibilities before deleting.") }
        case .support: navigation.open(.account, tab: .profile); session.fixNotice = blocker.detail + String(localized: " Ask your makerspace for help.")
        }
        if session.selectedSpace == maker, session.pendingAccountFix?.id == blocker.id { session.pendingAccountFix = nil }
    }
    private func destination(_ tab: AppTab) -> some View {
        NavigationStack(path: navigation.path(tab)) {
            DemoDestination(session: session, member: member, tab: tab, actions: actions, cart: cart, navigation: navigation, capabilities: capabilities, drafts: drafts, payments: payments, staff: staff, account: account, linkRouter: linkRouter)
                .navigationDestination(for: MemberRoute.self) { route in
                    MemberRouteView(route: route, member: member, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities, isDemo: true, payments: payments, staff: staff, account: account, onDemoDelete: session.reset, onDemoFix: session.routeAccountBlocker) {
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
    let payments: PaymentsState
    let staff: StaffState?
    let account: AccountState
    let linkRouter: MobileLinkRouter
    var body: some View {
        Group {
        if tab != .profile { MemberContent(state: member, tab: tab, name: session.name, selectTab: { navigation.selected = $0 }, actions: actions, cart: cart, navigation: navigation, drafts: drafts, paymentsAvailable: true, guidanceBookingsEnabled: capabilities.bootstrap?.modules.contains("bookable_spaces") == true, openLink: { text in
            guard let origin = try? ServerOrigin("https://demo.spaceworks.invalid") else { return }
            if let link = MobileLink.inbox(text, origin: origin) { linkRouter.receive(link) }
            else if let legacy = MobileLink.legacy(text, origin: origin) { linkRouter.receive(legacy) }
            else { linkRouter.refuseURL() }
        }) }
        else { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome back, \(session.name).").brandFont(.largeTitle, weight: .bold)
                Text(session.spaces[session.selectedSpace]).foregroundStyle(Color.swMuted)
                SWCard {
                        Text(session.role.rawValue).brandFont(.headline)
                        if capabilities.busy { ProgressView("Loading account options…") }
                        if let error = capabilities.error { SWError(message: error); Button("Retry account options") { Task { await capabilities.load() } }.frame(minHeight: 48) }
                        if capabilities.selfService { NavigationLink("Edit profile", value: MemberRoute.contact).frame(minHeight: 48) }
                        if capabilities.preferences { NavigationLink("Communication preferences", value: MemberRoute.preferences).frame(minHeight: 48) }
                        NavigationLink("Account and security", value: MemberRoute.account).frame(minHeight: 48).accessibilityIdentifier("account-entry")
                        if staff != nil { NavigationLink("Staff tools", value: MemberRoute.staff).frame(minHeight: 48).accessibilityIdentifier("staff-tools") }
                        NavigationLink("Payments", value: MemberRoute.payments).frame(minHeight: 48).accessibilityIdentifier("payments-entry")
                        NavigationLink("Notifications") {
                            DemoNotificationsView(state: session.notificationState, makerspaceID: session.selectedSpace + 7) { link in
                                let path: String
                                if case .product(let id) = link.destination { path = "/makerspaces/\(link.makerspaceID)/inventory/\(id)" }
                                else { path = "/makerspaces/\(link.makerspaceID)/inbox" }
                                if let hint = NotificationHint(payload: ["v": 2, "makerspace_id": link.makerspaceID, "link": path]) { linkRouter.receive(hint) }
                            }
                        }.frame(minHeight: 48).accessibilityIdentifier("notifications-entry")
                        Picker("Action preview result", selection: Binding(get: { session.actionScenario }, set: { session.actionScenario = $0 })) {
                            ForEach(DemoMemberActionsRepository.Scenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
                        }.frame(minHeight: 48).accessibilityIdentifier("action-preview-result")
                        NavigationLink("App guide") {
                            AppGuideView(isDemo: true, staffAvailable: staff != nil, replayTips: member.replayGuidance)
                        }.frame(minHeight: 48).accessibilityIdentifier("app-guide")
                        Button("Show helpful tips") { member.replayGuidance() }.frame(minHeight: 48)
                        Button("Sign out") { session.reset() }.frame(minHeight: 48)
                }
            }.padding(24).frame(maxWidth: 960).frame(maxWidth: .infinity)
        } }
        }.background(Color.swBg).navigationTitle(LocalizedStringKey(tab.rawValue))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(session.spaces.indices.filter { session.availableSpaces.contains($0) }, id: \.self) { index in Button(session.spaces[index]) { linkRouter.cancelIntent(); session.selectedSpace = index } }
                    } label: { Label(session.spaces[session.selectedSpace], systemImage: "building.2") }.accessibilityIdentifier("demo-makerspace-switcher")
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
