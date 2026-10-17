import SwiftUI

/// Task guidance contains no account data and never performs a server or SDK action.
struct AppGuideView: View {
    var isDemo = false
    var staffAvailable = false
    var serverLabel: String? = nil
    var replayTips: (() -> Void)? = nil
    @State private var replayIntroduction = false
    @State private var tipsReset = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("App guide").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("Make the most of your makerspace, at your own pace.").foregroundStyle(Color.swMuted)
                if isDemo { Text("Demo changes stay in this preview.").foregroundStyle(Color.swMuted) }
                SWCard {
                    Button("Replay introduction") { replayIntroduction = true }.frame(minHeight: 48).accessibilityIdentifier("guide-replay-introduction")
                    if let replayTips {
                        Button("Reset helpful tips") { replayTips(); tipsReset = true }.frame(minHeight: 48).accessibilityIdentifier("guide-reset-tips")
                        if tipsReset { Text("Helpful tips will appear again on Home.").foregroundStyle(Color.swMuted).accessibilityIdentifier("guide-tips-reset") }
                    }
                }
                SWCard {
                    DisclosureGroup {
                        Text("Use Home to see due loans, bookings, events and notices. Choose a makerspace from the switcher; your activity and permissions belong to that makerspace.").padding(.top, 8)
                    } label: { Label("Find your way around", systemImage: "map") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-navigation")
                    DisclosureGroup {
                        Text("Open Inventory, search or filter, then choose an item. Add the items you need and review quantities before submitting your request. Staff confirm availability, collection and borrowing terms.").padding(.top, 8)
                        Text("In Activity, check each active loan's due date. Choose Renew loan when available. A renewal is confirmed only when your makerspace returns a new due date.")
                    } label: { Label("Borrow tools", systemImage: "shippingbox") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-borrow")
                    DisclosureGroup {
                        Text("In Activity, choose Find a space. Set Starts and Ends, then choose Check availability. Review opening hours and booked times, complete any required answers and review your request. Pending approval is different from a confirmed booking.").padding(.top, 8)
                        Text("Open your booking to review its current status and available cancellation action. Confirm cancellation when prompted.")
                    } label: { Label("Book a space", systemImage: "calendar") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-bookings")
                    DisclosureGroup {
                        Text("Open an event, review its details and ticket choices, then confirm registration. Your result may be registered, awaiting approval or waitlisted. Open the confirmed registration in Activity to see its ticket.").padding(.top, 8)
                        Text("A ticket code is shown only while it remains valid. Staff verify attendance; displaying a code alone does not confirm check-in or payment.")
                    } label: { Label("Join events", systemImage: "ticket") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-events")
                    DisclosureGroup {
                        Text("Use Inbox for updates even when device notifications are off. In Profile, choose Notifications when you want alerts. Permission is requested only after you choose Enable notifications; you can change it later in Settings.").padding(.top, 8)
                        Text("Communication preferences control optional updates from your makerspace. Required safety messages remain on. Opening an update checks current access and reloads its destination.")
                    } label: { Label("Keep up to date", systemImage: "bell") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-notifications")
                    DisclosureGroup {
                        Text("Open Payments from Home, Activity or Profile. Review the amount, currency and charge before continuing to the configured checkout. The app checks the server after checkout; a payment is complete only when its status is confirmed.").padding(.top, 8)
                        Text("If confirmation is delayed, refresh the status before trying another payment. Open Receipts and credit notes to view or share an available document. Demo checkout never charges you.")
                    } label: { Label("Payments and receipts", systemImage: "creditcard") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-payments")
                    DisclosureGroup {
                        Text("In Profile, open Account and security to manage your password, two-step sign-in, verified phone and connected sign-in methods. Devices shows native app sessions; available makerspace Sessions are listed separately.").padding(.top, 8)
                        Text("Save new recovery codes before continuing. Some security changes end your sessions and require a fresh sign-in. A verified phone and an editable contact phone serve different purposes.")
                        Text("Cancel renewal keeps the current term as your makerspace permits; leaving ends that membership. Neither action deletes your whole account. Data exports and account deletion depend on the server's available account controls.")
                    } label: { Label("Protect your account", systemImage: "lock.shield") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-account")
                    if staffAvailable {
                        DisclosureGroup {
                            Text("Open Staff tools to review queues and approvals available to your role. Resolve the person or request before confirming an action. For issue, return or direct handout, check the items, capture required evidence and review the final confirmation.").padding(.top, 8)
                            Text("Scanning finds a record; it never confirms handover or attendance by itself. Check the resolved person, then choose Confirm check-in. If access changes or a conflict appears, refresh before continuing.")
                            Text("Camera permission is requested only when you choose Scan or Take evidence photo. If scanning is unavailable, use manual entry. Evidence photos require a camera; the app explains permission or hardware problems at that step.")
                        } label: { Label("Staff handovers and check-in", systemImage: "person.badge.key") }.frame(minHeight: 48, alignment: .leading).accessibilityIdentifier("guide-staff")
                    }
                }.foregroundStyle(Color.swInk)
                SWCard {
                    Text("About this app").brandFont(.title2, weight: .bold)
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
                    Text("Version \(version) (\(build))").textSelection(.enabled)
                    if let serverLabel { Text("Server").brandFont(.headline); Text(verbatim: serverLabel).textSelection(.enabled) }
                    if let privacy = Brand.privacyURL.flatMap(URL.init(string:)), let safe = AccountLinks.safe(privacy) { Link("Privacy policy", destination: safe).frame(minHeight: 48) }
                    if let support = Brand.supportURL.flatMap(URL.init(string:)), let safe = AccountLinks.safe(support) { Link("Contact support", destination: safe).frame(minHeight: 48) }
                    Text("Ask your makerspace for help with unavailable features, permissions or account records.").foregroundStyle(Color.swMuted)
                }
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("App guide").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.frame(minHeight: 48).accessibilityIdentifier("guide-done") } }
            .sheet(isPresented: $replayIntroduction) { IntroductionView { replayIntroduction = false } }
    }
}
