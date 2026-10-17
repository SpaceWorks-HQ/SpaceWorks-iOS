import SwiftUI
import SpaceWorksAPI

struct RootView: View {
    @State private var state = AppState()
    @State private var linkRouter = MobileLinkRouter()
    @State private var pendingURL: URL?
    @AppStorage("introduction-complete") private var introComplete = false
    #if DEBUG
    @State private var exploringDemo = false
    #endif
    var body: some View {
        Group {
            if !introComplete {
                IntroductionView { introComplete = true }
            } else {
            #if DEBUG
            if exploringDemo { DemoRoot { exploringDemo = false } }
            else { liveContent }
            #else
            liveContent
            #endif
            }
        }
        .tint(Color.swAccentInk)
        .foregroundStyle(Color.swInk)
        .preferredColorScheme(state.darkMode ? .dark : .light)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button { state.toggleAppearance() } label: {
                    Label(state.darkMode ? String(localized: "Light mode") : String(localized: "Dark mode"),
                          systemImage: state.darkMode ? "sun.max" : "moon")
                        .labelStyle(.iconOnly)
                        .font(.title3).frame(minWidth: 48, minHeight: 48)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain).foregroundStyle(Color.swAccentInk)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("appearance")
            }.background(Color.swSurface)
        }
        .nativePrivacyShield()
        .safeAreaInset(edge: .bottom) { MobileLinkNotice(router: linkRouter) }
        .task {
            installTapHandler()
            await state.restore()
        }
        .onChange(of: linkRouter.revision) { _, _ in Task { await linkRouter.process() } }
        .onOpenURL { url in
            #if DEBUG
            guard !exploringDemo else { return }
            #endif
            if NativeIdentity.handleGoogleCallback(url) || NativePayments.handleReturnURL(url) { return }
            if let origin = state.connectedOrigin { open(url, origin: origin) }
            else { pendingURL = url }
        }
        .onChange(of: state.connectedOrigin) { old, origin in
            if old != nil { linkRouter.reset(); pendingURL = nil }
            if let origin, let pendingURL { self.pendingURL = nil; open(pendingURL, origin: origin) }
            installTapHandler()
        }
    }
    private func installTapHandler() {
        NativeNotifications.shared.onTap = { hint in
            #if DEBUG
            guard !exploringDemo else { return }
            #endif
            linkRouter.receive(hint)
        }
    }
    private func open(_ url: URL, origin: ServerOrigin) {
        if let link = MobileLink.url(url, origin: origin) { linkRouter.receive(link) }
        else if let legacy = MobileLink.legacy(url.absoluteString, origin: origin) { linkRouter.receive(legacy) }
        else { linkRouter.refuseURL() }
    }
    private var liveContent: some View {
        VStack(spacing: 0) {
            switch state.screen {
            case .connect: ConnectView(state: state)
            case .shell:
                if let origin = state.connectedOrigin { AuthRoot(state: state, origin: origin, linkRouter: linkRouter) }
            }
            #if DEBUG
            if state.screen == .connect {
                Button("Explore demo") { exploringDemo = true }.frame(minHeight: 48).accessibilityIdentifier("explore-demo")
                    .frame(maxWidth: .infinity).background(Color.swSurface)
            }
            #endif
        }
    }
}

private struct ConnectView: View {
    @Bindable var state: AppState
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(Brand.appName).font(.headline).foregroundStyle(Color.swMuted)
                    BrandWordmark()
                    Text("Connect to your makerspace").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Enter the server address provided by your makerspace.").foregroundStyle(Color.swMuted)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server address").font(.headline)
                        TextField("Server address", text: $state.serverInput,
                                  prompt: Text(verbatim: "https://spaceworks.example").foregroundColor(Color.swMuted))
                            .foregroundStyle(Color.swInk)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.swOutline))
                            .accessibilityLabel("Server address").accessibilityIdentifier("server-url")
                            .disabled(state.locked || state.connecting)
                            .submitLabel(.go).onSubmit { Task { await state.connect() } }
                    }
                    if let error = state.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.swInk).accessibilityIdentifier("connection-error")
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                      Button { Task { await state.connect() } } label: {
                        HStack {
                            if state.connecting { ProgressView().tint(Color.swOnAccent) }
                            Text(state.connecting ? "Connecting…" : "Connect").frame(maxWidth: .infinity)
                        }.padding(16).frame(minHeight: 48)
                    }
                    .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.swOnAccent).disabled(state.connecting || (state.retryAfter ?? .distantPast) > timeline.date)
                    .accessibilityLabel(state.connecting ? "Connecting" : "Connect")
                    .accessibilityIdentifier("connect")
                    }
                }.padding(24).frame(maxWidth: 600)
            }.frame(maxWidth: .infinity).background(Color.swBg)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home", inventory = "Inventory", activity = "Activity", inbox = "Inbox", profile = "Profile"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .inventory: return "shippingbox"
        case .activity: return "clock"
        case .inbox: return "tray"
        case .profile: return "person.crop.circle"
        }
    }
}

struct AppShell: View {
    let state: AppState
    let auth: AuthState
    let linkRouter: MobileLinkRouter
    var body: some View {
        if let membership = auth.selectedMembership, let origin = state.connectedOrigin {
            MemberWorkspace(state: state, auth: auth, origin: origin, id: membership.id, slug: membership.slug, linkRouter: linkRouter)
                .id("\(origin.url.absoluteString).\(auth.user?.id ?? 0).\(membership.id)")
        }
    }
}

private struct MemberWorkspace: View {
    let state: AppState
    let auth: AuthState
    let linkRouter: MobileLinkRouter
    let makerspaceID: Int
    @State private var member: MemberState
    @State private var privateHolderOwner = UUID()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = MemberNavigation()
    @State private var cart: RequestCartState
    @State private var drafts: MemberActionDrafts
    @State private var capabilities: MemberCapabilities
    @State private var payments: PaymentsState
    @State private var account: AccountState?
    let actions: LiveMemberActionsRepository
    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    init(state: AppState, auth: AuthState, origin: ServerOrigin, id: Int, slug: String, linkRouter: MobileLinkRouter) {
        self.state = state; self.auth = auth; self.linkRouter = linkRouter; self.makerspaceID = id
        let failureHandlers = auth.repositoryFailureHandlers()
        let actions = LiveMemberActionsRepository(service: auth.service, expectedCredentials: auth.acceptedCredentials, id: id, slug: slug,
            onUnauthorized: failureHandlers.unauthorized, onForbidden: failureHandlers.forbidden)
        self.actions = actions
        _account = State(initialValue: auth.accountState(makerspaceID: id))
        _payments = State(initialValue: PaymentsState(repository: LivePaymentRepository(service: auth.service, expectedCredentials: auth.acceptedCredentials, makerspaceID: id, origin: origin,
            onUnauthorized: failureHandlers.unauthorized, onForbidden: failureHandlers.forbidden)))
        _cart = State(initialValue: RequestCartState(repository: actions))
        _drafts = State(initialValue: MemberActionDrafts(repository: actions))
        _capabilities = State(initialValue: MemberCapabilities(repository: actions, makerspaceID: id))
        _member = State(initialValue: MemberState(repository: LiveMemberRepository(service: auth.service, expectedCredentials: auth.acceptedCredentials, origin: origin, id: id, slug: slug,
            onUnauthorized: failureHandlers.unauthorized, onForbidden: failureHandlers.forbidden),
            settings: .standard, context: "\(origin.url.absoluteString).\(auth.user?.id ?? 0).\(id)"))
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
        // Keep the navigation host's identity stable when a phone rotates or a tablet window resizes.
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $preferredCompactColumn) {
                List(AppTab.allCases) { tab in
                    Button {
                        navigation.selected = tab
                        preferredCompactColumn = .detail
                        columns = geometry.size.width >= 1000 ? .all : .detailOnly
                    } label: {
                        Text(LocalizedStringKey(tab.rawValue)).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("nav-\(tab.rawValue)")
                        .foregroundStyle(navigation.selected == tab ? Color.swOnAccent : Color.swInk)
                        .listRowBackground(navigation.selected == tab ? Color.swSidebarActive : Color.swSidebar)
                }
                .scrollContentBackground(.hidden).background(Color.swSidebar)
                .navigationTitle(Brand.appName)
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
        }.task {
            auth.registerPrivateHolder(privateHolderOwner) { [member, cart, drafts, capabilities, navigation, payments, account] in
                member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); payments.invalidate(); account?.invalidate()
            }
            async let config: Void = capabilities.load(); await member.loadUnreadCount(); await config
        }.onDisappear {
            auth.unregisterPrivateHolder(privateHolderOwner)
            member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); payments.invalidate(); account?.invalidate()
        }
            .onChange(of: capabilities.selfService, initial: true) { _, _ in account?.updateCapabilities(selfService: capabilities.selfService, exports: capabilities.exports) }
            .onChange(of: capabilities.exports, initial: true) { _, _ in account?.updateCapabilities(selfService: capabilities.selfService, exports: capabilities.exports) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await capabilities.load(); await member.loadHome(); await member.loadUnreadCount() } }
            }
            .task(id: linkRouter.approved?.id) {
                if let approved = linkRouter.approved, approved.link.makerspaceID == makerspaceID {
                    await MobileLinkDestination.open(approved, router: linkRouter, member: member, navigation: navigation, drafts: drafts, payment: { id in
                        try await PaymentsLinkDestination.open(id, state: payments, navigation: navigation) { linkRouter.isCurrent(approved) }
                    })
                }
            }
            .onChange(of: auth.inboxRefreshRevision) { _, _ in
                guard auth.inboxRefreshMakerspaceID == makerspaceID else { return }
                Task { await member.loadInbox(); await member.loadUnreadCount() }
            }
            .onChange(of: sizeClass) { _, value in if value == .compact { navigation.compactInventory() } }
    }
    private func destination(_ tab: AppTab) -> some View {
        NavigationStack(path: navigation.path(tab)) {
            MemberScreen(state: state, auth: auth, member: member, tab: tab, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities, payments: payments, account: account, linkRouter: linkRouter)
                .navigationDestination(for: MemberRoute.self) { route in
                    MemberRouteView(route: route, member: member, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities, isDemo: false, payments: payments, account: account) { await auth.foreground() }
                }
        }
    }

}

private struct MemberScreen: View {
    let state: AppState
    let auth: AuthState
    let member: MemberState
    let tab: AppTab
    let actions: any MemberActionsRepository
    let cart: RequestCartState
    let drafts: MemberActionDrafts
    let navigation: MemberNavigation
    let capabilities: MemberCapabilities
    let payments: PaymentsState
    let account: AccountState?
    let linkRouter: MobileLinkRouter
    @State private var accountForm: AccountAccessState?
    @State private var replayIntro = false
    @State private var confirmSignOut = false
    var body: some View {
        Group {
        if tab != .profile { MemberContent(state: member, tab: tab, name: auth.displayName, selectTab: { navigation.selected = $0 }, actions: actions, cart: cart, navigation: navigation, drafts: drafts, paymentsAvailable: true, guidanceBookingsEnabled: capabilities.bootstrap?.modules.contains("bookable_spaces") == true, openLink: { text in
            guard let origin = state.connectedOrigin else { linkRouter.refuseURL(); return }
            if let link = MobileLink.inbox(text, origin: origin) { linkRouter.receive(link) }
            else if let legacy = MobileLink.legacy(text, origin: origin) { linkRouter.receive(legacy) }
            else { linkRouter.refuseURL() }
        }) }
        else { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                    SWCard {
                        Text(auth.displayName).font(.title2.bold())
                        Text(auth.user?.email ?? "").foregroundStyle(Color.swMuted).textSelection(.enabled)
                        if let error = auth.error { SWError(message: error) }
                        if auth.user?.email_verified == false {
                            Button("Confirm email") { accountForm = auth.accountForm(.emailVerification) }.frame(minHeight: 48)
                        }
                        if capabilities.busy { ProgressView("Loading account options…") }
                        if let error = capabilities.error { SWError(message: error); Button("Retry account options") { Task { await capabilities.load() } }.frame(minHeight: 48) }
                        if capabilities.selfService { NavigationLink("Edit profile", value: MemberRoute.contact).frame(minHeight: 48) }
                        if capabilities.preferences { NavigationLink("Communication preferences", value: MemberRoute.preferences).frame(minHeight: 48) }
                        if account != nil { NavigationLink("Account and security", value: MemberRoute.account).frame(minHeight: 48).accessibilityIdentifier("account-entry") }
                        NavigationLink("Payments", value: MemberRoute.payments).frame(minHeight: 48).accessibilityIdentifier("payments-entry")
                        if let notifications = auth.notifications {
                            NavigationLink("Notifications") { NotificationSettingsView(state: notifications) }.frame(minHeight: 48).accessibilityIdentifier("notifications-entry")
                        }
                        Button("Show introduction") { replayIntro = true }.frame(minHeight: 48)
                        NavigationLink("App guide") {
                            AppGuideView(serverLabel: state.connectedOrigin?.url.absoluteString, replayTips: member.replayGuidance)
                        }.frame(minHeight: 48).accessibilityIdentifier("app-guide")
                        Button("Show helpful tips") { member.replayGuidance() }.frame(minHeight: 48)
                        Button("Sign out", role: .destructive) { confirmSignOut = true }.frame(minHeight: 48).disabled(auth.busy)
                    }
            }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        } }
        }.background(Color.swBg).navigationTitle(LocalizedStringKey(tab.rawValue))
        .sheet(item: $accountForm) { form in AccountAccessView(form: form) { accountForm = nil } }
        .sheet(isPresented: $replayIntro) { IntroductionView { replayIntro = false } }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); payments.invalidate(); account?.invalidate(); Task { await auth.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll need to sign in again to use this account.") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(auth.memberships, id: \.id) { membership in
                        Button(membership.slug) {
                            guard auth.selectedID != membership.id else { return }
                            linkRouter.cancelIntent()
                            member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); payments.invalidate(); account?.invalidate()
                            Task { await auth.select(membership.id) }
                        }
                    }
                } label: { Label(auth.selectedMembership?.slug ?? String(localized: "Choose a makerspace"), systemImage: "building.2") }
                .accessibilityIdentifier("makerspace-switcher")
            }
        }
    }
}
