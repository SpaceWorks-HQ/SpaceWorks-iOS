import SwiftUI

/// Own global account state outside pushed destinations and before any makerspace is selected.
struct AccountMakerspaceLanding: View {
    let auth: AuthState
    @State private var account: AccountState?
    @State private var owner = UUID()
    init(auth: AuthState) { self.auth = auth; _account = State(initialValue: auth.accountState(makerspaceID: nil)) }
    var body: some View {
        NavigationStack { MakerspacePicker(auth: auth, account: account).navigationTitle("Your makerspaces").navigationBarTitleDisplayMode(.inline) }
            .task { auth.registerPrivateHolder(owner) { [account] in account?.invalidate() } }
            .onDisappear { auth.unregisterPrivateHolder(owner); account?.invalidate() }
    }
}
