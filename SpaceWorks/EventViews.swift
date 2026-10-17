import SwiftUI
import SpaceWorksAPI

struct EventDetailView: View {
    let event: Components.Schemas.PublicEvent
    let repository: any MemberActionsRepository
    let isDemo: Bool
    let completed: () async -> Void
    let viewActivity: () -> Void
    @State private var state: EventRegistrationState
    init(event: Components.Schemas.PublicEvent, repository: any MemberActionsRepository, isDemo: Bool, drafts: MemberActionDrafts? = nil, viewActivity: @escaping () -> Void = {}, completed: @escaping () async -> Void) {
        self.event = event; self.repository = repository; self.isDemo = isDemo; self.completed = completed; self.viewActivity = viewActivity
        _state = State(initialValue: drafts?.event(event) ?? EventRegistrationState(repository: repository, event: event))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isDemo { Text("Demo mode · no real event registration").font(.caption.bold()).foregroundStyle(Color.swMuted) }
                Text(event.title).font(.largeTitle.bold())
                Text(event.starts_at.formatted(date: .abbreviated, time: .shortened) + " · " + TimeZone.current.identifier).foregroundStyle(Color.swMuted)
                Label(event.location, systemImage: "mappin.and.ellipse")
                SWCard { Text("About the event").font(.title2.bold()); Text(event.description) }
                if let result = state.result {
                    SWCard {
                        Label(resultTitle(result.status.value1.rawValue), systemImage: "ticket").font(.title2.bold())
                        Text("Find this registration in Activity. Tickets appear only after registration is confirmed.").foregroundStyle(Color.swMuted)
                        Text("Payment and approval are confirmed by your makerspace. This receipt does not confirm a payment.").font(.caption).foregroundStyle(Color.swMuted)
                        Button("View registrations", action: viewActivity).buttonStyle(SWPrimary())
                    }
                } else if !event.registration_open { SWCard { Text("Registration is closed.").font(.headline) } }
                else {
                    SWCard {
                        Text("Register for this event").font(.title2.bold())
                        Text("Event fee: \(event.currency) \(event.payment_amount)").foregroundStyle(Color.swMuted)
                        if !event.ticket_types.isEmpty {
                            Picker("Ticket type", selection: $state.ticket) {
                                Text("Choose a ticket type").tag(Int?.none)
                                ForEach(Array(event.ticket_types.enumerated()), id: \.offset) { _, ticket in
                                    if let id = ticket.id {
                                        Text((ticket.name ?? String(localized: "Ticket")) + (ticket.amount.map { " · \(event.currency) \($0)" } ?? "")).tag(Int?.some(id))
                                    }
                                }
                            }.frame(minHeight: 48)
                        }
                        if event.registration_audience.value1 == .invite { input(String(localized: "Invitation code"), value: $state.invite).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        if event.promo_codes_enabled { input(String(localized: "Promo code (optional)"), value: $state.promo).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        input(String(localized: "Phone number (optional)"), value: $state.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                        input(String(localized: "Email (optional)"), value: $state.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        MemberCustomFields(form: state.form)
                        if let error = state.error { SWError(message: error) }
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Button(state.busy ? "Submitting…" : "Confirm registration") {
                                Task { await state.submit(); if state.result != nil { await completed() } }
                            }.buttonStyle(SWPrimary()).disabled(state.busy || state.form.unavailable || (state.retryAfter ?? .distantPast) > tick.date)
                        }
                    }.disabled(state.busy)
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Event details").scrollDismissesKeyboard(.interactively)
            .navigationBarBackButtonHidden(state.busy)
    }
    private func input(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            TextField(label, text: value).padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
        }
    }
    private func resultTitle(_ value: String) -> String {
        switch value { case "registered": return String(localized: "Registration confirmed"); case "waitlisted": return String(localized: "You're on the waitlist"); case "pending_approval": return String(localized: "Awaiting approval"); default: return String(localized: "Registration received") }
    }
}

struct MemberRegistrationView: View {
    let registration: Components.Schemas.MemberEventRegistrationActivity
    let isDemo: Bool
    let completed: () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: MemberTicketState
    @State private var confirmCancel = false
    init(registration: Components.Schemas.MemberEventRegistrationActivity, repository: any MemberActionsRepository, isDemo: Bool, drafts: MemberActionDrafts? = nil, completed: @escaping () async -> Void) {
        self.registration = registration; self.isDemo = isDemo; self.completed = completed
        _state = State(initialValue: drafts?.ticket(registration) ?? MemberTicketState(registration: registration, repository: repository))
    }
    var body: some View {
        ScrollView {
            SWCard {
                if isDemo { Text("Demo mode · sample event ticket").font(.caption.bold()).foregroundStyle(Color.swMuted) }
                Text(registration.event_title).font(.largeTitle.bold())
                Text(registration.starts_at.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Color.swMuted)
                Text(state.cancelled ? "Cancelled" : NativeStatusCopy.label(registration.status)).font(.headline)
                if let position = registration.waitlist_position, !state.cancelled { Text("Waitlist position: \(position)").foregroundStyle(Color.swMuted) }
                if state.cancelled { Text("Your registration was cancelled. Cancelling doesn't automatically issue a refund.").foregroundStyle(Color.swMuted) }
                else if registration.status == "registered" {
                    if state.busy { ProgressView("Loading your ticket…") }
                    else if state.image != nil && isDemo {
                        QRCodeView(value: "spaceworks-demo-event-ticket", label: "Simulated event ticket QR code")
                        Text("Simulated QR · demo only").font(.caption).foregroundStyle(Color.swMuted)
                    } else if let image = state.image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 340).accessibilityLabel("Event check-in QR code") }
                } else { Text("A ticket is available only after registration is confirmed.").foregroundStyle(Color.swMuted) }
                if let error = state.error {
                    if !state.cancelled && registration.status == "registered" { LoadFeedback(load: .failed(error), retryAfter: state.retryAfter) { await state.load() } }
                    else { SWError(message: error) }
                }
                if !state.cancelled && registration.can_cancel {
                    Text("Cancellation cutoff: \(registration.cancellation_cutoff_at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Color.swMuted)
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        Button("Cancel registration", role: .destructive) { confirmCancel = true }.frame(minHeight: 48)
                            .disabled(state.busy || (state.retryAfter ?? .distantPast) > tick.date)
                    }
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Event registration").privacySensitive()
            .task { await state.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await state.load() } } }
            .confirmationDialog("Cancel this registration?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel registration", role: .destructive) { Task { await state.cancel(); if state.cancelled { await completed() } } }
                Button("Keep registration", role: .cancel) {}
            } message: { Text("Your makerspace checks the cancellation cutoff. A cancellation does not automatically refund a settled payment.") }
    }
}
