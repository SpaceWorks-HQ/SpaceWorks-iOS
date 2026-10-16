import SwiftUI

struct RootView: View {
    @State private var state = AppState()
    var body: some View {
        Group {
            switch state.screen {
            case .connect: ConnectView(state: state)
            case .shell: AppShell(state: state)
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
                    .font(.body).frame(minHeight: 44).padding(.horizontal, 24)
                    .accessibilityIdentifier("appearance")
            }.background(Color.swSurface)
        }
        .task { await state.restore() }
    }
}

private struct ConnectView: View {
    @Bindable var state: AppState
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(Brand.appName).font(.headline).foregroundStyle(Color.swMuted)
                    Text("Connect to your Space Works server").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Your makerspace will share its server URL with you.").foregroundStyle(Color.swMuted)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL").font(.headline)
                        TextField("Server URL", text: $state.serverInput,
                                  prompt: Text("https://spaceworks.example").foregroundColor(Color.swMuted))
                            .foregroundStyle(Color.swInk)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.swOutline))
                            .accessibilityLabel("Server URL").accessibilityIdentifier("server-url")
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

private struct AppShell: View {
    let state: AppState
    var body: some View {
        TabView {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 16) {
                                if tab == .home {
                                    Text("Sign in").font(.title.bold()).accessibilityAddTraits(.isHeader)
                                    Text("Sign-in will be available in the next phase.").foregroundStyle(Color.swMuted)
                                }
                                Image(systemName: tab.symbol).font(.largeTitle).accessibilityHidden(true)
                                Text("Nothing here yet.").font(.body)
                                if tab == .profile && !state.locked {
                                    Button("Change server") { state.changeServer() }.frame(minHeight: 44)
                                }
                            }.padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                        .background(Color.swBg)
                    }
                        .navigationTitle(tab.rawValue)
                        .toolbarBackground(Color.swSurface, for: .navigationBar)
                }.tabItem { Label(tab.rawValue, systemImage: tab.symbol) }
            }
        }
        .toolbarBackground(Color.swSurface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Color.swAccentInk)
        // There is no Staff tab until A1 provides server-backed membership actions.
    }
}
