import SwiftUI
import SpaceWorksAPI

struct SpaceDiscoveryView: View {
    let member: MemberState
    let repository: any MemberActionsRepository
    let isDemo: Bool
    let completed: () async -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("Find a space").brandFont(.largeTitle, weight: .bold)
                Text("Make room for your next idea. Availability and approvals come from your makerspace.").foregroundStyle(Color.swMuted)
                if isDemo { Text("Demo mode · sample spaces").brandFont(.caption, weight: .bold).foregroundStyle(Color.swMuted) }
                LoadFeedback(load: member.spacesLoad, retryAfter: member.deadline("spaces")) { await member.loadSpaces() }
                if member.spacesLoad == .ready && member.spaces.isEmpty { SWCard { Text("Nothing here yet.").foregroundStyle(Color.swMuted) } }
                ForEach(member.spaces, id: \.public_token) { space in
                    NavigationLink(value: MemberRoute.space(space.public_token)) {
                        SWCard {
                            Label(space.name, systemImage: "building.2.crop.circle").brandFont(.title2, weight: .bold)
                            Text(space.description).foregroundStyle(Color.swMuted)
                            Text(space.location).foregroundStyle(Color.swMuted)
                            Text("Capacity: \(space.capacity)")
                            Label("View availability", systemImage: "arrow.right").foregroundStyle(Color.swAccentInk)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("space-\(space.public_token)")
                }
            }.padding(24).frame(maxWidth: 880, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Spaces").task { await member.loadSpaces() }
    }
}

struct SpaceBookingView: View {
    @State private var state: BookingState
    @State private var form: MemberCustomForm
    @State private var formError: String?
    let isDemo: Bool
    let completed: () async -> Void
    let viewActivity: () -> Void
    init(repository: any MemberActionsRepository, space: Components.Schemas.PublicBookableSpace, isDemo: Bool, drafts: MemberActionDrafts? = nil, viewActivity: @escaping () -> Void = {}, completed: @escaping () async -> Void) {
        _state = State(initialValue: drafts?.booking(space) ?? BookingState(repository: repository, space: space))
        _form = State(initialValue: drafts?.form(space) ?? MemberCustomForm(data: space.custom_form.flatMap { try? JSONEncoder().encode($0) }))
        self.isDemo = isDemo; self.completed = completed; self.viewActivity = viewActivity
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(state.space.name).brandFont(.largeTitle, weight: .bold)
                if isDemo { Text("Demo mode · no real booking is made").brandFont(.caption, weight: .bold).foregroundStyle(Color.swMuted) }
                if let result = state.result {
                    SWCard {
                        Label(result.status.value1 == .pending ? "Booking request received" : "Space booked", systemImage: "checkmark.circle").brandFont(.title2, weight: .bold)
                        Text(result.status.value1 == .pending ? "Staff must approve this request before the slot is confirmed." : "Your selected slot is confirmed and booked.").foregroundStyle(Color.swMuted)
                        Text("Find your booking in Activity. Its reference and cancellation options are loaded from your account.").foregroundStyle(Color.swMuted)
                        Button("View bookings", action: viewActivity).buttonStyle(SWPrimary())
                        Button("Book another slot") { form.text = [:]; form.multiple = [:]; state.startAnother() }.frame(minHeight: 48)
                    }
                } else {
                    SWCard {
                        Text("Request this space").brandFont(.title2, weight: .bold)
                        Text("Times are shown in your device timezone: \(TimeZone.current.identifier).").brandFont(.caption).foregroundStyle(Color.swMuted)
                        DatePicker("Starts", selection: $state.start).frame(minHeight: 48)
                        DatePicker("Ends", selection: $state.end).frame(minHeight: 48)
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Button(state.busy ? "Checking…" : "Check availability") { Task { await state.check() } }.buttonStyle(SWPrimary())
                                .disabled(state.busy || (state.retryAfter ?? .distantPast) > tick.date)
                        }
                    }.disabled(state.busy)
                    if let availability = state.availability {
                        SWCard {
                            Text("Opening hours").brandFont(.title2, weight: .bold)
                            Text(availability.timezone).brandFont(.caption).foregroundStyle(Color.swMuted)
                            if availability.opening_intervals.isEmpty { Text("The makerspace is closed in this window.").foregroundStyle(Color.swMuted) }
                            ForEach(Array(availability.opening_intervals.enumerated()), id: \.offset) { _, interval in Text(intervalLabel(interval.starts_at, interval.ends_at, timezone: availability.timezone)) }
                            if let intervals = availability.availability {
                                Text("Booked times").brandFont(.headline)
                                if intervals.isEmpty { Text("No confirmed bookings are shown in this window.").foregroundStyle(Color.swMuted) }
                                ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in Text(intervalLabel(interval.starts_at, interval.ends_at, timezone: availability.timezone)) }
                            } else { Text("This makerspace doesn't share booked times. Your request is checked when submitted.").foregroundStyle(Color.swMuted) }
                        }
                        SWCard {
                            Text("Booking details").brandFont(.title2, weight: .bold); MemberCustomFields(form: form)
                            Text("Review your times and answers. The server checks availability again when you submit.").foregroundStyle(Color.swMuted)
                            if let formError { SWError(message: formError) }
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                Button(state.busy ? "Submitting…" : "Submit booking request") { Task { await book() } }.buttonStyle(SWPrimary())
                                    .disabled(state.busy || form.unavailable || (state.retryAfter ?? .distantPast) > tick.date)
                            }
                        }.disabled(state.busy)
                    }
                    if let error = state.error { SWError(message: error) }
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Book a space").navigationBarBackButtonHidden(state.busy).scrollDismissesKeyboard(.interactively)
    }
    private func book() async {
        formError = nil
        guard let answers = form.validatedAnswers() else { formError = String(localized: "Check the highlighted questions."); return }
        do {
            let format = ISO8601DateFormatter()
            let body: [String: Any] = ["starts_at": format.string(from: state.start), "ends_at": format.string(from: state.end), "custom_answers": answers.isEmpty ? NSNull() : answers]
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let input = try decoder.decode(Components.Schemas.PublicBookingInput.self, from: JSONSerialization.data(withJSONObject: body))
            await state.confirm(input: input); if state.result != nil { await completed() }
        } catch { formError = String(localized: "These booking details could not be prepared. Check your answers and try again.") }
    }
}

private func intervalLabel(_ start: Date, _ end: Date, timezone: String) -> String {
    let format = DateFormatter(); format.locale = .current; format.dateStyle = .medium; format.timeStyle = .short
    format.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
    return format.string(from: start) + " – " + format.string(from: end)
}

struct MemberBookingDetailView: View {
    let booking: Components.Schemas.MemberBooking
    let repository: any MemberActionsRepository
    let isDemo: Bool
    let completed: () async -> Void
    @State private var updated: Components.Schemas.MemberBooking?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmation = false
    @State private var active = true
    @State private var retryAfter: Date?
    private var current: Components.Schemas.MemberBooking { updated ?? booking }
    var body: some View {
        ScrollView {
            SWCard {
                if isDemo { Text("Demo mode · sample booking").brandFont(.caption, weight: .bold).foregroundStyle(Color.swMuted) }
                Text(current.space_name).brandFont(.largeTitle, weight: .bold)
                Text(intervalLabel(current.starts_at, current.ends_at, timezone: current.timezone))
                Text(current.timezone).brandFont(.caption).foregroundStyle(Color.swMuted)
                Text(NativeStatusCopy.label(current.status.value1.rawValue)).brandFont(.headline)
                Text("Booking reference").brandFont(.headline); Text(current.public_token).font(.body.monospaced()).textSelection(.enabled)
                if let error { SWError(message: error) }
                if current.can_cancel {
                    Text("Cancellation cutoff: \(current.cancellation_cutoff_at.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted)
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        Button(busy ? "Cancelling…" : "Cancel booking", role: .destructive) { confirmation = true }.frame(minHeight: 48)
                            .disabled(busy || (retryAfter ?? .distantPast) > tick.date)
                    }
                } else { Text("Cancellation isn't available for this booking.").foregroundStyle(Color.swMuted) }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Booking details").navigationBarBackButtonHidden(busy).onDisappear { active = false }
            .confirmationDialog("Cancel this booking?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Cancel booking", role: .destructive) { Task { await cancel() } }
                Button("Keep booking", role: .cancel) {}
            } message: { Text("Your makerspace checks the cancellation cutoff. This does not automatically refund a payment.") }
    }
    private func cancel() async {
        guard active, !busy, current.can_cancel, (retryAfter ?? .distantPast) <= Date() else { return }
        busy = true; error = nil; defer { busy = false }
        do { let value = try await repository.cancelBooking(token: current.public_token); guard active else { return }; updated = value; await completed() }
        catch { if active { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) } }
    }
}
