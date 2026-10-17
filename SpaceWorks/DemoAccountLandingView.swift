#if DEBUG
import SwiftUI

/// A native account remains useful before joining a makerspace.
struct DemoAccountLandingView: View {
    let session: DemoSession
    @State private var account: AccountState
    init(session: DemoSession) { self.session = session; _account = State(initialValue: session.accountState(makerspaceID: nil)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BrandWordmark()
                    Text("Choose a makerspace").brandFont(.largeTitle, weight: .bold)
                    Text("You haven’t joined a makerspace yet.").foregroundStyle(Color.swMuted)
                    SWCard {
                        Text(session.name).brandFont(.title2, weight: .bold)
                        NavigationLink("Account and security") {
                            AccountView(state: account, privacyURL: Brand.privacyURL.flatMap(URL.init(string:)), supportURL: Brand.supportURL.flatMap(URL.init(string:)), onDemoDelete: session.reset)
                        }.frame(minHeight: 48).accessibilityIdentifier("account-entry")
                        Button("Sign out") { account.invalidate(); session.reset() }.frame(minHeight: 48)
                    }
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background(Color.swBg).navigationTitle("Your makerspaces").navigationBarTitleDisplayMode(.inline)
        }.onDisappear { account.invalidate() }
    }
}
#endif
