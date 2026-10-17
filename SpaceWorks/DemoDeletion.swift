#if DEBUG
import Foundation
import Observation
import SwiftUI

/// A local preview of the planned account-deletion journey. This has no transport or SDK dependency.
@MainActor @Observable
final class DemoDeletionState {
    enum Stage: Equatable { case explanation, blockers, reauthenticate, confirm, deleted }
    enum Scenario: String, CaseIterable { case blocked = "Outstanding obligations", ready = "Ready to delete", conflict = "Obligation added at confirmation" }
    enum Method: String, CaseIterable { case password = "Password", authenticator = "Authenticator", phone = "Phone code" }
    enum Destination: String { case payments = "Payments", activity = "Activity", bookings = "Bookings", events = "Events", staff = "Staff tools", support = "Makerspace support" }
    struct Blocker: Identifiable, Equatable {
        let id: String
        let makerspace: String
        let count: Int
        let detail: String
        let destination: Destination
    }
    private(set) var stage = Stage.explanation
    private(set) var blockers: [Blocker] = []
    private(set) var error: String?
    private(set) var active = true
    var scenario = Scenario.blocked { didSet { if scenario != oldValue { observedConflict = false } } }
    private var observedConflict = false
    var method = Method.password
    var credential = ""
    var confirmation = ""
    private var proofExpires: Date?
    private let now: () -> Date
    private let onDelete: () -> Void
    init(now: @escaping () -> Date = Date.init, onDelete: @escaping () -> Void = {}) { self.now = now; self.onDelete = onDelete }
    var canConfirm: Bool { active && stage == .confirm && confirmation == "DELETE" && (proofExpires ?? .distantPast) > now() }
    func checkBlockers() {
        guard active, stage != .deleted else { return }
        credential = ""; confirmation = ""; proofExpires = nil; error = nil
        blockers = scenario == .blocked ? Self.sampleBlockers : scenario == .conflict && observedConflict ? [Self.sampleBlockers[3]] : []
        stage = blockers.isEmpty ? .reauthenticate : .blockers
    }
    func authenticate() {
        guard active, stage == .reauthenticate, blockers.isEmpty else { return }
        let valid = method == .password ? credential == "DemoPass!123" : credential == "123456"
        credential = ""
        guard valid else { error = method == .password ? String(localized: "That password didn't work. Try again.") : String(localized: "Invalid or expired verification code."); return }
        proofExpires = now().addingTimeInterval(300); confirmation = ""; error = nil; stage = .confirm
    }
    func deletePreviewAccount() {
        guard active, stage == .confirm else { return }
        guard (proofExpires ?? .distantPast) > now() else {
            proofExpires = nil; confirmation = ""; error = String(localized: "Verify your identity again before deleting."); stage = .reauthenticate; return
        }
        guard confirmation == "DELETE" else { error = String(localized: "Type DELETE to confirm."); return }
        if scenario == .conflict {
            observedConflict = true
            blockers = [Self.sampleBlockers[3]]; proofExpires = nil; confirmation = ""; stage = .blockers
            error = String(localized: "An obligation changed. Review the updated blockers before continuing."); return
        }
        credential = ""; confirmation = ""; proofExpires = nil; blockers = []; error = nil; stage = .deleted
        // Only the demo owner may clear its in-memory session. No real account operation exists here.
        onDelete()
    }
    func invalidate() { active = false; credential = ""; confirmation = ""; proofExpires = nil; blockers = []; error = nil }
    static let sampleBlockers: [Blocker] = [
        .init(id: "unpaid_charges", makerspace: "Fab Lab Kochi", count: 2, detail: String(localized: "Settle outstanding charges before deleting your account."), destination: .payments),
        .init(id: "refund_in_progress", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "A refund is still being processed."), destination: .payments),
        .init(id: "deposit_held", makerspace: "Maker Space Bengaluru", count: 1, detail: String(localized: "A deposit is still held by the makerspace."), destination: .payments),
        .init(id: "active_loans", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "Return all borrowed equipment first."), destination: .activity),
        .init(id: "open_requests", makerspace: "Maker Space Bengaluru", count: 1, detail: String(localized: "Resolve open equipment requests."), destination: .activity),
        .init(id: "accountability_open", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "An accountability review needs attention."), destination: .support),
        .init(id: "open_service_jobs", makerspace: "Maker Space Bengaluru", count: 1, detail: String(localized: "A service job is still open."), destination: .support),
        .init(id: "upcoming_bookings", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "Cancel or complete upcoming bookings."), destination: .bookings),
        .init(id: "upcoming_registrations", makerspace: "Maker Space Bengaluru", count: 1, detail: String(localized: "Cancel or complete upcoming event registrations."), destination: .events),
        .init(id: "last_manager", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "Assign another manager before leaving this makerspace."), destination: .staff),
        .init(id: "organization_owner", makerspace: "Maker Space Bengaluru", count: 1, detail: String(localized: "Transfer organization ownership first."), destination: .support),
        .init(id: "superadmin", makerspace: "This server", count: 1, detail: String(localized: "Use the web console to resolve server administration responsibilities."), destination: .support),
        .init(id: "future_server_blocker", makerspace: "Fab Lab Kochi", count: 1, detail: String(localized: "A makerspace review must finish before deletion can proceed."), destination: .support)
    ]
}

struct DemoDeletionView: View {
    @State private var state: DemoDeletionState
    var onFix: ((DemoDeletionState.Blocker) -> Void)?
    @State private var passwordFocused = false
    @FocusState private var fieldFocused: Bool
    init(onFix: ((DemoDeletionState.Blocker) -> Void)? = nil, onDelete: @escaping () -> Void) {
        _state = State(initialValue: DemoDeletionState(onDelete: onDelete)); self.onFix = onFix
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Delete account").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Label("Demo only · no account will be deleted", systemImage: "info.circle").foregroundStyle(Color.swMuted)
            Text("This deletes your whole Space Works account on this server, across every makerspace.").font(.headline)
            Text("Payment and loan history is kept anonymised for legal and accounting records. Leaving one makerspace is a separate action.").foregroundStyle(Color.swMuted)
            if let error = state.error { SWError(message: error) }
            if state.stage == .explanation || state.stage == .blockers {
                Picker("Deletion preview", selection: $state.scenario) { ForEach(DemoDeletionState.Scenario.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                    .accessibilityIdentifier("deletion-scenario")
                Button(state.stage == .explanation ? "Check account obligations" : "Check again") { state.checkBlockers() }
                    .buttonStyle(SWPrimary()).accessibilityIdentifier("deletion-check")
            }
            switch state.stage {
            case .explanation: Text("Review every makerspace's obligations, verify your identity, then confirm. You can leave at any time before confirmation.").foregroundStyle(Color.swMuted)
            case .blockers:
                Text("Resolve these before deleting").font(.title2.bold())
                ForEach(state.blockers) { blocker in
                    SWCard {
                        Text(blocker.makerspace).font(.headline)
                        Text(blocker.detail)
                        Text("\(blocker.count) outstanding").font(.subheadline).foregroundStyle(Color.swMuted)
                        if let onFix { Button("Open \(blocker.destination.rawValue)") { onFix(blocker) }.frame(minHeight: 48) }
                        else { NavigationLink("Open \(blocker.destination.rawValue)") { DemoDeletionResolutionView(blocker: blocker) }.frame(minHeight: 48) }
                    }
                }
            case .reauthenticate:
                Text("Verify your identity").font(.title2.bold())
                Picker("Verification method", selection: $state.method) { ForEach(DemoDeletionState.Method.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }
                    .onChange(of: state.method) { _, _ in state.credential = "" }
                if state.method == .password {
                    PasswordControl(title: String(localized: "Current password"), text: $state.credential, identifier: "deletion-password", focus: $passwordFocused)
                    Text("Use DemoPass!123 for this demo.").foregroundStyle(Color.swMuted)
                } else {
                    TextField("Verification code", text: $state.credential).textContentType(.oneTimeCode).keyboardType(.numberPad).focused($fieldFocused)
                        .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("deletion-code")
                    Text("Use 123456 for this demo. No message or authenticator request was sent.").foregroundStyle(Color.swMuted)
                }
                Button("Verify identity") { state.authenticate() }.buttonStyle(SWPrimary()).accessibilityIdentifier("deletion-verify")
            case .confirm:
                Text("Confirm deletion").font(.title2.bold())
                Text("Type DELETE to clear this demo account. This preview only resets in-memory sample data.").foregroundStyle(Color.swMuted)
                TextField("Type DELETE", text: $state.confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled().focused($fieldFocused)
                    .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("deletion-confirmation")
                Button("Delete demo account", role: .destructive) { state.deletePreviewAccount() }.buttonStyle(SWPrimary()).disabled(!state.canConfirm).accessibilityIdentifier("deletion-submit")
            case .deleted: Label("Demo account cleared", systemImage: "checkmark.circle").font(.title2.bold())
            }
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline).onDisappear { state.credential = ""; state.confirmation = "" }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { fieldFocused = false; passwordFocused = false } } }
    }
}

private struct DemoDeletionResolutionView: View {
    let blocker: DemoDeletionState.Blocker
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text(LocalizedStringKey(blocker.destination.rawValue)).font(.largeTitle.bold()); Text(blocker.makerspace).font(.headline)
            Text(blocker.detail); Text("This preview does not resolve real obligations. Open the matching makerspace task from your account to continue.").foregroundStyle(Color.swMuted)
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle(LocalizedStringKey(blocker.destination.rawValue))
    }
}
#endif
