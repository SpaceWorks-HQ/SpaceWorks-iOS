import SwiftUI

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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected = AppTab.home
    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(AppTab.allCases) { tab in
                    Button { selected = tab } label: {
                        Text(tab.rawValue).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("nav-\(tab.rawValue)")
                        .foregroundStyle(selected == tab ? Color.swOnAccent : Color.swInk)
                        .listRowBackground(selected == tab ? Color.swSidebarActive : Color.swSidebar)
                }
                .scrollContentBackground(.hidden).background(Color.swSidebar)
                .navigationTitle(Brand.appName)
            } detail: { NavigationStack { MemberScreen(state: state, auth: auth, tab: selected) } }
        } else {
            TabView(selection: $selected) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack { MemberScreen(state: state, auth: auth, tab: tab) }
                        .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }.tag(tab)
                }
            }
        }
    }
}

private struct MemberScreen: View {
    let state: AppState
    let auth: AuthState
    let tab: AppTab
    @State private var accountForm: AccountAccessState?
    @State private var replayIntro = false
    @State private var confirmSignOut = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if tab == .home {
                    Text("Welcome back, \(auth.displayName).").font(.largeTitle.bold())
                    Text("Your makerspace, in your pocket.").foregroundStyle(Color.swMuted)
                }
                if tab == .profile {
                    SWCard {
                        Text(auth.displayName).font(.title2.bold())
                        Text(auth.user?.email ?? "").foregroundStyle(Color.swMuted).textSelection(.enabled)
                        if let error = auth.error { SWError(message: error) }
                        if auth.user?.email_verified == false {
                            Button("Confirm email") { accountForm = auth.accountForm(.emailVerification) }.frame(minHeight: 48)
                        }
                        Button("Show introduction") { replayIntro = true }.frame(minHeight: 48)
                        Button("Sign out", role: .destructive) { confirmSignOut = true }.frame(minHeight: 48).disabled(auth.busy)
                    }
                } else {
                    SWCard {
                        Image(systemName: tab.symbol).font(.title).accessibilityHidden(true)
                        Text("Nothing here yet.").font(.headline)
                    }
                }
            }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle(tab.rawValue)
        .sheet(item: $accountForm) { form in AccountAccessView(form: form) { accountForm = nil } }
        .sheet(isPresented: $replayIntro) { IntroductionView { replayIntro = false } }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll need to sign in again to use this account.") }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(auth.memberships, id: \.id) { membership in
                        Button(membership.slug) { Task { await auth.select(membership.id) } }
                    }
                } label: { Label(auth.selectedMembership?.slug ?? "Choose a makerspace", systemImage: "building.2") }
                .accessibilityIdentifier("makerspace-switcher")
            }
        }
    }
}
