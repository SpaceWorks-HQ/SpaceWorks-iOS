import SwiftUI
import SpaceWorksAPI

/// Existing authenticated booking records for the current account/makerspace only.
struct MemberBookingsView: View {
    @Bindable var state: MemberState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Bookings").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                NavigationLink("Find a space", value: MemberRoute.spaces).frame(minHeight: 48)
                LoadFeedback(load: state.bookingsLoad, lastUpdated: state.updated["bookings"], retryAfter: state.deadline("bookings")) { await state.loadBookings() }
                if state.bookingsLoad == .ready && state.bookings.isEmpty {
                    SWCard { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
                }
                ForEach(state.bookings, id: \.public_token) { row in
                    SWCard {
                        NavigationLink(row.space_name, value: MemberRoute.booking(row.public_token)).font(.headline).frame(minHeight: 48)
                        Text(guideBookingDate(row.starts_at, timezone: row.timezone))
                        Text(NativeStatusCopy.label(row.status.value1.rawValue)).foregroundStyle(Color.swMuted)
                    }
                }
                if state.bookingsHasMore {
                    Button("Load more bookings") { Task { await state.loadBookings(more: true) } }.frame(minHeight: 48).disabled(state.bookingsLoad == .loading)
                }
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Bookings").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("member-bookings-list")
            .task { await state.loadBookings() }.refreshable { await state.loadBookings() }
    }
}

private func guideBookingDate(_ date: Date, timezone: String) -> String {
    let zone = TimeZone(identifier: timezone)
    let formatter = DateFormatter()
    formatter.locale = .current; formatter.dateStyle = .medium; formatter.timeStyle = .short
    formatter.timeZone = zone ?? TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date) + " · " + (zone == nil ? "UTC" : timezone)
}
