import SwiftUI
import SpaceWorksAPI

struct RootView: View {
    @State private var state = AppState()
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
                Button(state.darkMode ? "Light mode" : "Dark mode") { state.toggleAppearance() }
                    .buttonStyle(.plain).foregroundStyle(Color.swAccentInk)
                    .font(.body).frame(minHeight: 48).padding(.horizontal, 24)
                    .accessibilityIdentifier("appearance")
            }.background(Color.swSurface)
        }
        .nativePrivacyShield()
        .task { await state.restore() }
    }
    private var liveContent: some View {
        VStack(spacing: 0) {
            switch state.screen {
            case .connect: ConnectView(state: state)
            case .shell:
                if let origin = state.connectedOrigin { AuthRoot(state: state, origin: origin) }
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
    var body: some View {
        if let membership = auth.selectedMembership, let origin = state.connectedOrigin {
            MemberWorkspace(state: state, auth: auth, origin: origin, id: membership.id, slug: membership.slug)
                .id("\(origin.url.absoluteString).\(auth.user?.id ?? 0).\(membership.id)")
        }
    }
}

private struct MemberWorkspace: View {
    let state: AppState
    let auth: AuthState
    @State private var member: MemberState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = MemberNavigation()
    @State private var cart: RequestCartState
    @State private var drafts: MemberActionDrafts
    @State private var capabilities: MemberCapabilities
    let actions: LiveMemberActionsRepository
    @State private var columns = NavigationSplitViewVisibility.automatic
    init(state: AppState, auth: AuthState, origin: ServerOrigin, id: Int, slug: String) {
        self.state = state; self.auth = auth
        let actions = LiveMemberActionsRepository(service: auth.service, id: id, slug: slug,
            onUnauthorized: { [weak auth] message in await auth?.invalidateSession(message: message) },
            onForbidden: { [weak auth] in await auth?.foreground() })
        self.actions = actions
        _cart = State(initialValue: RequestCartState(repository: actions))
        _drafts = State(initialValue: MemberActionDrafts(repository: actions))
        _capabilities = State(initialValue: MemberCapabilities(repository: actions, makerspaceID: id))
        _member = State(initialValue: MemberState(repository: LiveMemberRepository(service: auth.service, origin: origin, id: id, slug: slug,
            onUnauthorized: { [weak auth] message in await auth?.invalidateSession(message: message) },
            onForbidden: { [weak auth] in await auth?.foreground() }),
            settings: .standard, context: "\(origin.url.absoluteString).\(auth.user?.id ?? 0).\(id)"))
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $columns) {
                List(AppTab.allCases) { tab in
                    Button {
                        navigation.selected = tab
                        columns = geometry.size.width >= 1000 ? .all : .detailOnly
                    } label: {
                        Text(tab.rawValue).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await capabilities.load(); await member.loadHome(); await member.loadUnreadCount() } }
            }
            .onChange(of: sizeClass) { _, value in if value == .compact { navigation.compactInventory() } }
    }
    private func destination(_ tab: AppTab) -> some View {
        NavigationStack(path: navigation.path(tab)) {
            MemberScreen(state: state, auth: auth, member: member, tab: tab, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities)
                .navigationDestination(for: MemberRoute.self) { route in
                    MemberRouteView(route: route, member: member, actions: actions, cart: cart, drafts: drafts, navigation: navigation, capabilities: capabilities, isDemo: false) { await auth.foreground() }
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
    @State private var accountForm: AccountAccessState?
    @State private var replayIntro = false
    @State private var confirmSignOut = false
    var body: some View {
        Group {
        if tab != .profile { MemberContent(state: member, tab: tab, name: auth.displayName, selectTab: { navigation.selected = $0 }, actions: actions, cart: cart, navigation: navigation, drafts: drafts) }
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
                        Button("Show introduction") { replayIntro = true }.frame(minHeight: 48)
                        Button("Show helpful tips") { member.replayGuidance() }.frame(minHeight: 48)
                        Button("Sign out", role: .destructive) { confirmSignOut = true }.frame(minHeight: 48).disabled(auth.busy)
                    }
            }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        } }
        }.background(Color.swBg).navigationTitle(tab.rawValue)
        .sheet(item: $accountForm) { form in AccountAccessView(form: form) { accountForm = nil } }
        .sheet(isPresented: $replayIntro) { IntroductionView { replayIntro = false } }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate(); Task { await auth.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll need to sign in again to use this account.") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(auth.memberships, id: \.id) { membership in
                        Button(membership.slug) {
                            guard auth.selectedID != membership.id else { return }
                            member.invalidate(); cart.invalidate(); drafts.invalidate(); capabilities.invalidate(); navigation.invalidate()
                            Task { await auth.select(membership.id) }
                        }
                    }
                } label: { Label(auth.selectedMembership?.slug ?? "Choose a makerspace", systemImage: "building.2") }
                .accessibilityIdentifier("makerspace-switcher")
            }
        }
    }
}
