import SwiftUI
import SpaceWorksAPI

struct StaffView: View {
    @Bindable var state: StaffState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Staff tools").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("Review, hand over, and welcome people into your makerspace.").foregroundStyle(Color.swMuted)
                if state.isDemo { Label("Demo staff tools · sample data", systemImage: "info.circle").foregroundStyle(Color.swMuted) }
                SWCard {
                    if ["accept_request", "reject_request", "issue_request", "return_request"].contains(where: state.can) {
                        NavigationLink { StaffRequestsView(state: state) } label: { StaffMenuRow(title: Text("Requests and loans"), detail: "Review requests and guide equipment handovers", symbol: "shippingbox") }.accessibilityIdentifier("staff-requests")
                    }
                    if state.can("issue_direct_loan") || state.canReturn {
                        NavigationLink { StaffDirectLoansView(state: state) } label: { StaffMenuRow(title: Text("Direct handout"), detail: "Choose a borrower, equipment, and evidence", symbol: "person.crop.rectangle") }.accessibilityIdentifier("staff-direct")
                    }
                    if state.can("manage_bookings") {
                        NavigationLink { StaffSpacesView(state: state) } label: { StaffMenuRow(title: Text("Booking approvals"), detail: "Review space reservations", symbol: "calendar") }.accessibilityIdentifier("staff-bookings")
                    }
                    if state.can("manage_events") {
                        NavigationLink { StaffEventsView(state: state) } label: { StaffMenuRow(title: Text("Event check-in"), detail: "Scan, review the person, then confirm attendance", symbol: "qrcode.viewfinder") }.accessibilityIdentifier("staff-events")
                    }
                }
                Text("Only the tools allowed by your selected makerspace appear here.").brandFont(.subheadline).foregroundStyle(Color.swMuted)
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk).navigationTitle("Staff tools")
    }
}

private struct StaffMenuRow: View {
    let title: Text; let detail: LocalizedStringKey; let symbol: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    title.brandFont(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(detail).brandFont(.subheadline).foregroundStyle(Color.swMuted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: symbol).font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) { title.brandFont(.headline); Text(detail).brandFont(.subheadline).foregroundStyle(Color.swMuted) }
                    Spacer(minLength: 0); Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
        }.frame(minHeight: 64).padding(.vertical, 12).foregroundStyle(Color.swInk)
    }
}

struct StaffRequestsView: View {
    @Bindable var state: StaffState
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Picker("Request queue", selection: $state.queue) {
                    Text("Pending review").tag(StaffQueue.pending); Text("Ready for issue").tag(StaffQueue.accepted); Text("Active loans").tag(StaffQueue.active)
                }.pickerStyle(.menu).frame(minHeight: 48).accessibilityIdentifier("staff-request-queue")
                StaffFeedback(load: state.load) { await state.loadQueue() }
                if let error = state.error { SWError(message: error) }
                if let notice = state.notice { Label(notice, systemImage: "checkmark.circle").accessibilityIdentifier("staff-request-notice") }
                if state.load == .ready && state.requests.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
                ForEach(state.requests, id: \.id) { row in
                    NavigationLink { StaffRequestDetail(state: state, row: row) } label: {
                        SWCard {
                            Text(row.requester_display.isEmpty ? row.requester_username : row.requester_display).brandFont(.headline).foregroundStyle(Color.swInk)
                            Text("Request #\(row.id) · \(NativeStatusCopy.label(row.status))").foregroundStyle(Color.swMuted)
                            ForEach(row.items, id: \.id) { item in Text("\(item.product_name) × \(state.queue == .pending ? item.requested_quantity : item.accepted_quantity)").foregroundStyle(Color.swInk) }
                            Label("Review details", systemImage: "chevron.right").brandFont(.subheadline)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("staff-request-\(row.id)")
                }
                if state.nextQueuePage != nil { Button("Load more requests") { Task { await state.loadQueue(more: true) } }.frame(minHeight: 48) }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Requests and loans").navigationBarTitleDisplayMode(.inline)
            .task(id: state.queue) { await state.loadQueue() }.refreshable { await state.loadQueue() }
    }
}

private struct StaffRequestDetail: View {
    @Bindable var state: StaffState
    let row: Components.Schemas.AdminRequest
    @State private var quantities: [Int: Int] = [:]
    @State private var reason = ""
    @State private var decision: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(row.requester_display.isEmpty ? row.requester_username : row.requester_display).brandFont(.largeTitle, weight: .bold)
                Text("Request #\(row.id) · \(NativeStatusCopy.label(row.status))").foregroundStyle(Color.swMuted)
                ForEach(row.items, id: \.id) { item in
                    SWCard {
                        Text(item.product_name).brandFont(.headline)
                        if !item.storage_location.isEmpty { Label(item.storage_location, systemImage: "mappin").foregroundStyle(Color.swMuted) }
                        Text("Requested: \(item.requested_quantity) · Accepted: \(item.accepted_quantity)")
                        if state.queue == .pending && state.can("accept_request") {
                            Stepper("Accept \(quantities[item.id] ?? item.requested_quantity)", value: Binding(get: { quantities[item.id] ?? item.requested_quantity }, set: { quantities[item.id] = $0 }), in: 0...max(0, item.requested_quantity)).frame(minHeight: 48).accessibilityLabel("Accepted quantity for \(item.product_name)").accessibilityValue("\(quantities[item.id] ?? item.requested_quantity)")
                        }
                    }
                }
                if let error = state.error { SWError(message: error) }
                if state.queue == .pending {
                    if state.can("accept_request") { Button("Accept request") { decision = "accept" }.buttonStyle(SWPrimary()).disabled(!state.canRequest) }
                    if state.can("reject_request") {
                        TextField("Reason for rejection", text: $reason, axis: .vertical).lineLimit(3...6).modifier(StaffInput()).disabled(state.busy).accessibilityIdentifier("staff-rejection-reason")
                        Button("Reject request", role: .destructive) { decision = "reject" }.frame(minHeight: 48).disabled(!state.canRequest || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else if state.queue == .accepted && state.canIssue {
                    NavigationLink("Start guided issue") { StaffHandoverView(state: StaffHandoverState(parent: state, mode: .issue(row))) }.buttonStyle(SWPrimary())
                } else if state.queue == .active && state.canReturn {
                    NavigationLink("Start guided return") { StaffHandoverView(state: StaffHandoverState(parent: state, mode: .returnRequest(row))) }.buttonStyle(SWPrimary())
                }
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Request details").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(decision == "accept" ? "Accept this request?" : "Reject this request?", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), titleVisibility: .visible) {
                if decision == "accept" { Button("Confirm acceptance") { Task { await state.accept(row, quantities: quantities); if state.error == nil { dismiss() } } } }
                else { Button("Confirm rejection", role: .destructive) { Task { await state.reject(row, reason: reason); if state.error == nil { dismiss() } } } }
                Button("Cancel", role: .cancel) { decision = nil }
            }
            .onAppear { if quantities.isEmpty { quantities = Dictionary(uniqueKeysWithValues: row.items.map { ($0.id, $0.requested_quantity) }) } }
    }
}

private struct StaffDirectLoansView: View {
    @Bindable var state: StaffState
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if state.can("issue_direct_loan") && state.can("upload_evidence") {
                    NavigationLink("Start direct handout") { StaffHandoverView(state: StaffHandoverState(parent: state, mode: .directIssue)) }.buttonStyle(SWPrimary())
                }
                StaffFeedback(load: state.directLoad) { await state.loadDirect() }
                ForEach(state.directLoans, id: \.id) { row in
                    SWCard {
                        Text(row.target_label).brandFont(.headline); Text("Loan #\(row.id) · \(NativeStatusCopy.label(row.status))").foregroundStyle(Color.swMuted)
                        if let due = row.due_at { Text("Due \(due.formatted(date: .abbreviated, time: .shortened))") }
                        if row.status == "active" && state.canReturn {
                            NavigationLink("Record return") { StaffHandoverView(state: StaffHandoverState(parent: state, mode: .directReturn(row))) }.frame(minHeight: 48)
                        }
                    }
                }
                if state.directLoad == .ready && state.directLoans.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
                if state.nextDirectPage != nil { Button("Load more loans") { Task { await state.loadDirect(more: true) } }.frame(minHeight: 48) }
            }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Direct handout").navigationBarTitleDisplayMode(.inline).task { await state.loadDirect() }.refreshable { await state.loadDirect() }
    }
}

private struct StaffEventsView: View {
    @Bindable var state: StaffState
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            StaffFeedback(load: state.eventsLoad) { await state.loadEvents() }
            ForEach(state.events, id: \.id) { event in
                NavigationLink { StaffCheckInView(state: StaffCheckInState(parent: state, event: event)) } label: {
                    SWCard { Text(event.title).brandFont(.headline).foregroundStyle(Color.swInk); Text(event.starts_at, format: .dateTime.day().month().hour().minute()).foregroundStyle(Color.swMuted); Label("Open check-in", systemImage: "qrcode.viewfinder") }
                }.buttonStyle(.plain)
            }
            if state.eventsLoad == .ready && state.events.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            if state.nextEventPage != nil { Button("Load more events") { Task { await state.loadEvents(more: true) } }.frame(minHeight: 48) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Event check-in").navigationBarTitleDisplayMode(.inline).task { await state.loadEvents() }.refreshable { await state.loadEvents() }
    }
}

private struct StaffCheckInView: View {
    @State var state: StaffCheckInState
    @State private var scanner = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            if !state.parent.isActive {
                SWError(message: state.parent.error ?? String(localized: "Your access changed. Return to your makerspace before continuing."))
                Button("Close") { dismiss() }.buttonStyle(SWPrimary())
            } else {
            Text(state.eventTitle).brandFont(.largeTitle, weight: .bold)
            Text("Scan a check-in code. Review the person below before recording attendance.").foregroundStyle(Color.swMuted)
            Button("Scan check-in code") { scanner = true }.buttonStyle(SWPrimary()).disabled(state.busy)
            if state.busy { ProgressView("Checking registration…") }
            if let error = state.error { SWError(message: error) }
            if let confirmation = state.confirmation { Label(confirmation, systemImage: "checkmark.circle").brandFont(.headline).accessibilityIdentifier("staff-attendance-recorded") }
            if let person = state.person {
                SWCard {
                    Text(person.name).brandFont(.title2, weight: .bold); Text(NativeStatusCopy.label(person.status))
                    Text("Payment: \((person.payment_status ?? String(localized: "Unavailable")).replacingOccurrences(of: "_", with: " "))").foregroundStyle(Color.swMuted)
                    if state.canConfirm { Button("Confirm attendance") { Task { await state.confirm() } }.buttonStyle(SWPrimary()).accessibilityIdentifier("staff-confirm-attendance") }
                    else { Text("This registration cannot be checked in. Scan another code or ask the event manager.").foregroundStyle(Color.swMuted) }
                }
            }
            }
        }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Check-in").navigationBarTitleDisplayMode(.inline)
            .nativeFeedback(state.feedback)
            .sheet(isPresented: $scanner) { NativeQRScanner(title: String(localized: "Check-in code")) { value in scanner = false; Task { await state.resolve(value) } } }
    }
}

private struct StaffSpacesView: View {
    @Bindable var state: StaffState
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            StaffFeedback(load: state.spacesLoad) { await state.loadSpaces() }
            ForEach(state.spaces, id: \.id) { space in
                NavigationLink { StaffBookingsView(state: state, spaceID: space.id, name: space.name) } label: { SWCard { StaffMenuRow(title: Text(verbatim: space.name), detail: "Review reservations", symbol: "calendar") } }.buttonStyle(.plain)
            }
            if state.spacesLoad == .ready && state.spaces.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            if state.nextSpacePage != nil { Button("Load more spaces") { Task { await state.loadSpaces(more: true) } }.frame(minHeight: 48) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle("Booking approvals").navigationBarTitleDisplayMode(.inline).task { await state.loadSpaces() }.refreshable { await state.loadSpaces() }
    }
}

private struct StaffBookingsView: View {
    @Bindable var state: StaffState
    let spaceID: Int; let name: String
    @State private var decision: (row: Components.Schemas.BookingAdmin, approve: Bool)?
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            StaffFeedback(load: state.bookingsLoad) { await state.loadBookings(spaceID: spaceID) }
            if let error = state.error { SWError(message: error) }
            if let notice = state.notice { Text(notice).accessibilityIdentifier("staff-booking-notice") }
            ForEach(state.bookings, id: \.id) { row in
                SWCard {
                    Text(row.name).brandFont(.headline); Text(row.starts_at, format: .dateTime.day().month().hour().minute())
                    Text(NativeStatusCopy.label(row.status.value1.rawValue)).foregroundStyle(Color.swMuted)
                    if !row.note.isEmpty { Text(row.note) }
                    if row.status.value1.rawValue == "pending" {
                        Button("Approve booking") { decision = (row, true) }.buttonStyle(SWPrimary()).disabled(!state.canRequest)
                        Button("Reject booking", role: .destructive) { decision = (row, false) }.frame(minHeight: 48).disabled(!state.canRequest)
                    }
                }
            }
            if state.bookingsLoad == .ready && state.bookings.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            if state.nextBookingPage != nil { Button("Load more bookings") { Task { await state.loadBookings(spaceID: spaceID, more: true) } }.frame(minHeight: 48) }
        }.padding(24).frame(maxWidth: 900).frame(maxWidth: .infinity) }.background(Color.swBg).navigationTitle(name).navigationBarTitleDisplayMode(.inline).task { await state.loadBookings(spaceID: spaceID) }.refreshable { await state.loadBookings(spaceID: spaceID) }
            .confirmationDialog(decision?.approve == true ? "Approve this booking?" : "Reject this booking?", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), titleVisibility: .visible) {
                if let decision { Button(decision.approve ? "Confirm approval" : "Confirm rejection") { Task { await state.decideBooking(decision.row, approve: decision.approve); self.decision = nil } } }
                Button("Cancel", role: .cancel) { decision = nil }
            }
    }
}

struct StaffFeedback: View {
    let load: StaffState.Load
    let retry: () async -> Void
    var body: some View {
        switch load {
        case .loading: ProgressView("Loading…")
        case .failed(let message): SWError(message: message); Button("Try again") { Task { await retry() } }.frame(minHeight: 48)
        default: EmptyView()
        }
    }
}

struct StaffInput: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).frame(minHeight: 48).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).foregroundStyle(Color.swInk)
    }
}
