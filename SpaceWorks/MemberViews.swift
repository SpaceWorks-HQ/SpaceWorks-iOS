import SwiftUI
import SpaceWorksAPI
import ImageIO

struct MemberContent: View {
    @Bindable var state: MemberState
    let tab: AppTab
    let name: String
    var selectTab: (AppTab) -> Void = { _ in }
    @State private var showCard = false
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            switch tab {
            case .inventory: InventoryList(state: state)
            case .inbox: MemberInbox(state: state)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if tab == .home {
                            Text("Welcome back, \(name).").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            Text("Your makerspace, at a glance.").foregroundStyle(Color.swMuted)
                            if state.showGuidance {
                                SWCard {
                                    HStack { Text("Start here").font(.headline); Spacer(); Button("Dismiss") { state.dismissGuidance() }.frame(minHeight: 48) }
                                    Text("Find what you need, then request it from your makerspace.").foregroundStyle(Color.swMuted)
                                    Button("Browse inventory") { selectTab(.inventory) }.buttonStyle(SWPrimary())
                                    Button("View bookings") { selectTab(.activity) }.frame(minHeight: 48)
                                }
                            }
                        }
                        LazyVGrid(columns: textSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 320), spacing: 24)], alignment: .leading, spacing: 24) {
                            loans
                            if tab == .activity { requests }
                            bookings
                            events
                            if tab == .home {
                                dues
                                SWCard {
                                    Label("Membership card", systemImage: "person.text.rectangle").font(.title2.bold())
                                    Text("Keep your membership details close. Ask the front desk for help if your card isn't available.").foregroundStyle(Color.swMuted)
                                    Button("View membership card") { showCard = true }.frame(minHeight: 48)
                                }
                                notices
                            }
                        }
                    }.padding(24).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                }.refreshable { await state.loadHome() }
            }
        }.background(Color.swBg)
            .task(id: tab) {
                switch tab {
                case .home, .activity: await state.loadHome()
                case .inventory: if state.inventoryLoad == .idle { await state.loadInventory() }
                case .inbox: if state.inboxLoad == .idle { await state.loadInbox() }
                case .profile: break
                }
            }
            .sheet(isPresented: $showCard) { MemberCardView(state: state) }
    }
    private var loans: some View {
        SWCard {
            Label("Active loans", systemImage: "shippingbox").font(.title2.bold())
            LoadFeedback(load: state.activityLoad, lastUpdated: state.updated["activity"]) { await state.loadActivity() }
            if let activity = state.activity {
                if activity.active_hardware_loans.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
                ForEach(activity.active_hardware_loans, id: \.request_id) { loan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loan.label).font(.headline)
                        if let due = loan.due_at { Label("Due \(due.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar") }
                        if loan.overdue { Label("Overdue", systemImage: "exclamationmark.circle").foregroundStyle(Color.swDanger) }
                        else { Text("On loan").foregroundStyle(Color.swMuted) }
                    }.padding(.vertical, 8)
                }
            }
        }
    }
    private var requests: some View {
        SWCard {
            Label("Requests", systemImage: "list.clipboard").font(.title2.bold())
            LoadFeedback(load: state.activityLoad) { await state.loadActivity() }
            if let rows = state.activity?.request_history, !rows.isEmpty {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                        Text("\(row.item_count) items · \(row.created_at.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Color.swMuted)
                    }
                }
            } else if state.activityLoad == .ready { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
        }
    }
    private var bookings: some View {
        SWCard {
            Label("Upcoming bookings", systemImage: "calendar").font(.title2.bold())
            LoadFeedback(load: state.bookingsLoad, lastUpdated: state.updated["bookings"]) { await state.loadBookings() }
            if state.bookingsLoad == .ready && state.bookings.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            ForEach(state.bookings, id: \.public_token) { booking in
                VStack(alignment: .leading, spacing: 8) {
                    Text(booking.space_name).font(.headline)
                    Text(memberDate(booking.starts_at, timezone: booking.timezone))
                    Text(booking.status.value1.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(Color.swMuted)
                }.padding(.vertical, 8)
            }
            if state.bookingsHasMore { Button("Load more bookings") { Task { await state.loadBookings(more: true) } }.frame(minHeight: 48).disabled(state.bookingsLoad == .loading) }
        }
    }
    private var events: some View {
        SWCard {
            Label("Events", systemImage: "ticket").font(.title2.bold())
            LoadFeedback(load: state.eventsLoad, lastUpdated: state.updated["events"]) { await state.loadEvents() }
            if state.eventsLoad == .ready && state.events.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            ForEach(state.events, id: \.public_token) { event in
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.headline)
                    Text(memberDate(event.starts_at, timezone: TimeZone.current.identifier)).foregroundStyle(Color.swMuted)
                }.padding(.vertical, 8)
            }
        }
    }
    private var notices: some View {
        SWCard {
            Label("Notices", systemImage: "megaphone").font(.title2.bold())
            if let rows = state.activity?.notices, !rows.isEmpty {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, notice in
                    VStack(alignment: .leading, spacing: 8) { Text(notice.title).font(.headline); Text(notice.body).foregroundStyle(Color.swMuted) }
                }
            } else if state.activityLoad == .ready { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
        }
    }
    private var dues: some View {
        SWCard {
            Label("Dues", systemImage: "creditcard").font(.title2.bold())
            if state.activityLoad == .loading || state.activityLoad == .idle {
                LoadFeedback(load: state.activityLoad) { await state.loadActivity() }
            } else {
            if let dues = state.activity?.membership_dues, let encoded = try? JSONEncoder().encode(dues),
               let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any],
               let amounts = object["outstanding_by_currency"] as? [String: String] {
                if amounts.isEmpty { Text("No dues outstanding.") }
                ForEach(amounts.keys.sorted(), id: \.self) { currency in Text("\(currency) \(amounts[currency] ?? "")").font(.title2.bold()).monospacedDigit() }
            } else { Text("Dues are unavailable. Try again later.").foregroundStyle(Color.swMuted) }
            }
        }
    }
}

struct LoadFeedback: View {
    let load: MemberState.Load
    var lastUpdated: Date?
    let retry: () async -> Void
    var body: some View {
        switch load {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 12) {
                ProgressView("Loading…")
                RoundedRectangle(cornerRadius: 4).fill(Color.swSurface).frame(height: 12).accessibilityHidden(true)
                RoundedRectangle(cornerRadius: 4).fill(Color.swSurface).frame(maxWidth: 180, minHeight: 12, maxHeight: 12).accessibilityHidden(true)
            }.frame(minHeight: 80)
        case .failed(let message):
            VStack(alignment: .leading) {
                SWError(message: message)
                if let lastUpdated { Text("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Color.swMuted) }
                Button("Try again") { Task { await retry() } }.frame(minHeight: 48)
            }
        case .ready: EmptyView()
        }
    }
}

struct InventoryList: View {
    @Bindable var state: MemberState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var selectedProduct: Int?
    var body: some View {
        GeometryReader { geometry in
            let split = sizeClass == .regular && geometry.size.width >= 850 && !textSize.isAccessibilitySize
            HStack(spacing: 0) {
                inventory(split: split).frame(maxWidth: split ? 440 : .infinity)
                if split {
                    Rectangle().fill(Color.swOutline).frame(width: 1)
                    if let selectedProduct {
                        InventoryDetail(repository: state.repository, id: selectedProduct).id(selectedProduct)
                    } else {
                        ContentUnavailableView("Choose an item", systemImage: "shippingbox", description: Text("See availability and borrowing terms here."))
                            .foregroundStyle(Color.swMuted).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
    private func inventory(split: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Find what you need, then request it from your makerspace.").foregroundStyle(Color.swMuted)
                HStack {
                    TextField("Search inventory", text: $state.search,
                              prompt: Text("Search inventory").foregroundColor(Color.swMuted))
                        .submitLabel(.search).onSubmit { Task { await state.loadInventory() } }.accessibilityIdentifier("inventory-search")
                    Button("Search") { Task { await state.loadInventory() } }.frame(minHeight: 48)
                }.padding(.horizontal, 14).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
                Menu {
                    Button("All categories") { state.category = nil; Task { await state.loadInventory() } }
                    ForEach(state.categories, id: \.id) { category in
                        Button(category.name) { state.category = category.slug; Task { await state.loadInventory() } }
                    }
                } label: { Label(state.categories.first(where: { $0.slug == state.category })?.name ?? "All categories", systemImage: "line.3.horizontal.decrease.circle") }.frame(minHeight: 48)
                LoadFeedback(load: state.inventoryLoad, lastUpdated: state.updated["inventory"]) { await state.loadInventory() }
                if state.inventoryLoad == .ready && state.products.isEmpty {
                    SWCard {
                        Text(state.search.isEmpty && state.category == nil ? "No items yet" : "No items match these filters").font(.headline)
                        if !state.search.isEmpty || state.category != nil {
                            Button("Clear filters") { state.search = ""; state.category = nil; Task { await state.loadInventory() } }.frame(minHeight: 48)
                        }
                    }
                }
                ForEach(state.products, id: \.id) { product in
                    if split {
                        Button { selectedProduct = product.id } label: { productRow(product) }
                            .buttonStyle(.plain).accessibilityIdentifier("product-\(product.id)")
                            .accessibilityAddTraits(selectedProduct == product.id ? .isSelected : [])
                    } else {
                        NavigationLink { InventoryDetail(repository: state.repository, id: product.id) } label: { productRow(product) }
                            .buttonStyle(.plain).accessibilityIdentifier("product-\(product.id)")
                    }
                }
                if state.inventoryHasMore { Button("Load more") { Task { await state.loadInventory(more: true) } }.buttonStyle(SWPrimary()).disabled(state.inventoryLoad == .loading) }
            }.padding(24).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        }.refreshable { await state.loadInventory() }
    }
    private func productRow(_ product: Components.Schemas.PublicProduct) -> some View {
        SWCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shippingbox").font(.title).frame(width: 48, height: 48).background(Color.swSurface, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.name).font(.headline)
                    if let category = product.category_name { Text(category).foregroundStyle(Color.swMuted) }
                    Text(availability(product)).foregroundStyle(Color.swMuted)
                }
                Spacer(minLength: 0); Image(systemName: "chevron.right").accessibilityHidden(true)
            }
        }
    }
}

private func availability(_ product: Components.Schemas.PublicProduct) -> String {
    guard let value = product.availability else { return "Ask your makerspace about availability." }
    if let count = value.count, value.mode == .exact_count { return "\(count) available" }
    return value.label?.rawValue ?? "Ask your makerspace about availability."
}

private func memberDate(_ date: Date, timezone: String) -> String {
    let zone = TimeZone(identifier: timezone)
    let formatter = DateFormatter()
    formatter.locale = .current; formatter.dateStyle = .medium; formatter.timeStyle = .short
    formatter.timeZone = zone ?? TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date) + " · " + (zone == nil ? "UTC" : timezone)
}

struct InventoryDetail: View {
    let repository: any MemberRepository
    let id: Int
    @State private var product: Components.Schemas.PublicProduct?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let product {
                    Text(product.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(availability(product)).foregroundStyle(Color.swMuted)
                    SWCard { Text("About this item").font(.title2.bold()); Text(product.description) }
                    SWCard { Text("Borrowing terms").font(.title2.bold()); Text(product.borrowing_terms.isEmpty ? "Ask your makerspace about borrowing this item." : product.borrowing_terms) }
                } else if let error {
                    SWCard { SWError(message: error); Button("Try again") { Task { await load() } }.frame(minHeight: 48) }
                } else { ProgressView("Loading item…") }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Item details").task { await load() }
            .onDisappear { product = nil }
    }
    private func load() async {
        product = nil; error = nil
        do { let result = try await repository.product(id); guard !Task.isCancelled else { return }; product = result }
        catch { self.error = APIError.display(error) }
    }
}

struct MemberInbox: View {
    @Bindable var state: MemberState
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Messages", selection: $state.unreadOnly) { Text("All").tag(false); Text("Unread").tag(true) }.pickerStyle(.segmented)
                    .onChange(of: state.unreadOnly) { _, _ in Task { await state.loadInbox() } }
                Button("Mark all as read") { Task { await state.markAllRead() } }.frame(minHeight: 48).disabled(state.inboxMutating)
                LoadFeedback(load: state.inboxLoad, lastUpdated: state.updated["inbox"]) { await state.loadInbox() }
                if state.inboxLoad == .ready && state.messages.isEmpty { SWCard { Text("Nothing here yet.").foregroundStyle(Color.swMuted) } }
                ForEach(state.messages, id: \.id) { message in
                    SWCard {
                        HStack { Text(message.title).font(.headline); Spacer(); if message.read_at == nil { Label("Unread", systemImage: "circle.fill").font(.caption).foregroundStyle(Color.swAccentInk) } }
                        Text(message.summary).foregroundStyle(Color.swMuted)
                        Text(message.created_at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.swMuted)
                        if message.read_at == nil { Button("Mark as read") { Task { await state.markRead(message.id) } }.frame(minHeight: 48).disabled(state.inboxMutating) }
                    }
                }
                if state.inboxHasMore { Button("Load more") { Task { await state.loadInbox(more: true) } }.buttonStyle(SWPrimary()).disabled(state.inboxLoad == .loading) }
            }.padding(24).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        }.refreshable { await state.loadInbox() }
    }
}

struct MemberCardView: View {
    let state: MemberState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                SWCard {
                    if state.repository.isDemo { Text("Demo mode · sample data").font(.caption.bold()).foregroundStyle(Color.swMuted) }
                    Text("Membership card").font(.largeTitle.bold())
                    LoadFeedback(load: state.cardLoad) { await state.loadCard() }
                    if let card = state.card, card.is_active {
                        Text(card.printed_name).font(.title2.bold())
                        Text("Card \(card.card_number)").monospacedDigit()
                        if card.qr_active, let image = card.qr_image.flatMap(Self.qrImage) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 320).accessibilityLabel("Membership card QR code")
                        } else if card.qr_active && state.repository.isDemo {
                            QRCodeView(value: "spaceworks-demo-member-card", label: "Simulated membership card QR code")
                            Text("Simulated QR · demo only").foregroundStyle(Color.swMuted)
                        } else { Text("Your card QR code isn't available. Ask the front desk for help.").foregroundStyle(Color.swMuted) }
                    } else if state.cardLoad == .ready { Text("Your membership card isn't active. Ask the front desk for help.").foregroundStyle(Color.swMuted) }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Color.swBg).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.frame(minHeight: 48) } }
        }.privacySensitive().task { await state.loadCard() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await state.loadCard() } } }
    }
    private static func qrImage(_ value: String) -> UIImage? {
        let prefix = "data:image/png;base64,"
        guard value.hasPrefix(prefix), value.utf8.count <= 2_000_000,
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...2048).contains(width), (1...2048).contains(height) else { return nil }
        return UIImage(data: data)
    }
}
