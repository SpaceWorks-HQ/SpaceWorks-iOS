import SwiftUI

struct ProfileEditorView: View {
    @State private var state: ProfileEditorState
    let isDemo: Bool
    let saved: () async -> Void
    @State private var discardConfirmation = false
    @State private var wantsExit = false
    @FocusState private var focusedField: String?
    @Environment(\.dismiss) private var dismiss
    init(repository: any MemberActionsRepository, isDemo: Bool, drafts: MemberActionDrafts? = nil, saved: @escaping () async -> Void = {}) {
        _state = State(initialValue: drafts?.profile ?? ProfileEditorState(repository: repository)); self.isDemo = isDemo; self.saved = saved
    }
    var body: some View {
        ScrollView {
            SWCard {
                if isDemo { Text("Demo mode · sample profile").brandFont(.caption, weight: .bold).foregroundStyle(Color.swMuted) }
                Text("Edit profile").brandFont(.largeTitle, weight: .bold)
                Text("Your contact details in this makerspace. Changing a phone number here doesn't verify it for sign-in.").foregroundStyle(Color.swMuted)
                if state.loaded {
                    field(String(localized: "Display name"), value: $state.displayName, identifier: "profile-display-name", content: .name)
                    field(String(localized: "First name"), value: $state.firstName, identifier: "profile-first-name", content: .givenName)
                    field(String(localized: "Last name"), value: $state.lastName, identifier: "profile-last-name", content: .familyName)
                    field(String(localized: "Phone number"), value: $state.phone, identifier: "profile-phone", content: .telephoneNumber)
                    if state.dirty { Text("Unsaved changes").brandFont(.caption).foregroundStyle(Color.swMuted) }
                    else if let notice = state.notice { Label(notice, systemImage: "checkmark.circle").foregroundStyle(Color.swAccentInk) }
                    if let error = state.error { SWError(message: error) }
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        Button(state.busy ? "Saving…" : "Save changes") { Task { await state.save(); if !state.dirty && state.notice != nil { await saved() } } }
                            .buttonStyle(SWPrimary()).disabled(state.busy || !state.dirty || (state.retryAfter ?? .distantPast) > tick.date)
                    }
                    Button("Discard changes") { wantsExit = false; discardConfirmation = true }.frame(minHeight: 48).disabled(state.busy || !state.dirty)
                } else if let error = state.error {
                    SWError(message: error); Button("Try again") { Task { await state.load() } }.frame(minHeight: 48)
                } else { ProgressView("Loading profile…") }
            }.disabled(state.busy).padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Profile details").scrollDismissesKeyboard(.interactively)
            .navigationBarBackButtonHidden(state.dirty || state.busy).interactiveDismissDisabled(state.dirty || state.busy)
            .toolbar {
                if focusedField != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { focusedField = nil }
                            .accessibilityLabel(Text("Done")).accessibilityIdentifier("profile-keyboard-done")
                    }
                }
                if state.dirty || state.busy { ToolbarItem(placement: .topBarLeading) { Button("Back") { wantsExit = true; discardConfirmation = true }.frame(minHeight: 48).disabled(state.busy) } }
            }
            .task { if !state.dirty { await state.load() } }
            .confirmationDialog("Discard your changes?", isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { state.discard(); if wantsExit { dismiss() } }
                Button("Keep editing", role: .cancel) { wantsExit = false }
            } message: { Text("Your saved profile will stay as it was.") }
    }
    private func field(_ label: String, value: Binding<String>, identifier: String, content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).brandFont(.headline)
            TextField(label, text: value).textContentType(content).autocorrectionDisabled()
                .focused($focusedField, equals: identifier).submitLabel(.done).onSubmit { focusedField = nil }
                .keyboardType(content == .telephoneNumber ? .phonePad : .default)
                .padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier(identifier)
        }
    }
}

struct CommunicationPreferencesView: View {
    @State private var state: CommunicationPreferencesState
    let isDemo: Bool
    let digestsEnabled: Bool
    init(repository: any MemberActionsRepository, isDemo: Bool, drafts: MemberActionDrafts? = nil, digestsEnabled: Bool = true) { _state = State(initialValue: drafts?.preferences ?? CommunicationPreferencesState(repository: repository)); self.isDemo = isDemo; self.digestsEnabled = digestsEnabled }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Communication preferences").brandFont(.largeTitle, weight: .bold)
                Text("Choose optional updates for this makerspace. Required safety messages stay on. Device notification permission is a separate setting.").foregroundStyle(Color.swMuted)
                if isDemo { Text("Demo mode · no real preferences are changed").brandFont(.caption, weight: .bold).foregroundStyle(Color.swMuted) }
                if let error = state.error { SWError(message: error) }
                if !state.loaded {
                    if state.error != nil { Button("Try again") { Task { await state.load() } }.frame(minHeight: 48) }
                    else { ProgressView("Loading preferences…") }
                } else if state.cells.isEmpty { SWCard { Text("Nothing here yet.").foregroundStyle(Color.swMuted) } }
                ForEach(Array(state.cells.enumerated()), id: \.offset) { _, cell in
                    SWCard {
                        Text(NativeStatusCopy.label(cell.feature.rawValue)).brandFont(.headline)
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Toggle(channel(cell.channel.rawValue), isOn: Binding(get: { cell.enabled }, set: { value in Task { await state.set(cell, enabled: value) } }))
                                .accessibilityIdentifier("preference-\(cell.feature.rawValue)-\(cell.channel.rawValue)")
                                .frame(minHeight: 48).disabled(state.busy || (!cell.available && !cell.enabled) || (state.retryAfter ?? .distantPast) > tick.date)
                            if digestsEnabled, cell.channel.rawValue == "email", let digest = cell.daily_digest {
                                Toggle("Daily email digest", isOn: Binding(get: { digest }, set: { value in Task { await state.digest(cell, enabled: value) } }))
                                    .frame(minHeight: 48).disabled(state.busy || !cell.available || !cell.enabled || (state.retryAfter ?? .distantPast) > tick.date)
                            }
                        }
                        if !cell.available { Text("Unavailable in this makerspace.").brandFont(.caption).foregroundStyle(Color.swMuted) }
                        if !cell.mandatory_events.isEmpty {
                            Text("Always-on safety messages: \(cell.mandatory_events.map(NativeStatusCopy.label).joined(separator: ", "))").brandFont(.caption).foregroundStyle(Color.swMuted)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Communication").task(id: digestsEnabled) { state.digestsAllowed = digestsEnabled; await state.load() }
    }
    private func channel(_ value: String) -> String {
        switch value { case "email": return String(localized: "Email"); case "in_app": return String(localized: "In-app inbox"); case "native_push": return String(localized: "Push notifications"); default: return value }
    }
}
