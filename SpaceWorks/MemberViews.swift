import SwiftUI
import SpaceWorksAPI
import ImageIO

struct MemberContent: View {
    @Bindable var state: MemberState
    let tab: AppTab
    let name: String
    var selectTab: (AppTab) -> Void = { _ in }
    var actions: (any MemberActionsRepository)? = nil
    var cart: RequestCartState? = nil
    var navigation: MemberNavigation? = nil
    var drafts: MemberActionDrafts? = nil
    var paymentsAvailable = false
    var guidanceBookingsEnabled = true
    var openLink: ((String) -> Void)? = nil
    @State private var showCard = false
    @State private var renewal: Components.Schemas.MemberLoanActivity?
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Group {
            switch tab {
            case .inventory: InventoryList(state: state, cart: cart, navigation: navigation, drafts: drafts)
            case .inbox: MemberInbox(state: state, openLink: openLink)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if tab == .home {
                            Text("Welcome back, \(name).").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            Text("Your makerspace, at a glance.").foregroundStyle(Color.swMuted)
                            if state.showGuidance {
                                SWCard {
                                    HStack { Text("Start here").font(.headline); Spacer(); Button("Dismiss") { state.dismissGuidance() }.frame(minHeight: 48).accessibilityIdentifier("guidance-dismiss") }
                                    Text("Find what you need, then request it from your makerspace.").foregroundStyle(Color.swMuted)
                                    Button("Browse inventory") { selectTab(.inventory) }.buttonStyle(SWPrimary())
                                    if guidanceBookingsEnabled { Button("View bookings") { if let navigation { navigation.openBookings() } else { selectTab(.activity) } }.frame(minHeight: 48) }
                                    else { Button("View profile") { selectTab(.profile) }.frame(minHeight: 48) }
                                }
                            }
                        }
                        LazyVGrid(columns: textSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .topLeading)] : [GridItem(.adaptive(minimum: 320), spacing: 24, alignment: .topLeading)], alignment: .leading, spacing: 24) {
                            loans
                            if tab == .activity {
                                if paymentsAvailable { SWCard { NavigationLink("Payments", value: MemberRoute.payments).frame(minHeight: 48) } }
                                requests; registrations
                            }
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
            .sheet(isPresented: Binding(get: { renewal != nil }, set: { if !$0 { renewal = nil } })) {
                if let renewal, let actions { RenewLoanView(loan: renewal, repository: actions, isDemo: state.repository.isDemo) { await state.loadActivity() } }
            }
    }
    private var loans: some View {
        SWCard {
            Label("Active loans", systemImage: "shippingbox").font(.title2.bold())
            LoadFeedback(load: state.activityLoad, lastUpdated: state.updated["activity"], retryAfter: state.deadline("activity")) { await state.loadActivity() }
            if let activity = state.activity {
                if activity.active_hardware_loans.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
                ForEach(activity.active_hardware_loans, id: \.request_id) { loan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loan.label).font(.headline)
                        if let due = loan.due_at { Label("Due \(due.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar") }
                        if loan.overdue { Label("Overdue", systemImage: "exclamationmark.circle").foregroundStyle(Color.swDanger) }
                        else { Text("On loan").foregroundStyle(Color.swMuted) }
                        if actions != nil {
                            Button("Renew loan") { renewal = loan }.frame(minHeight: 48).disabled(!loan.can_renew)
                            if !loan.can_renew { Text(loan.renewal_refusal ?? String(localized: "Renewal isn't available for this loan. Ask your makerspace for help.")).font(.caption).foregroundStyle(Color.swMuted) }
                        }
                    }.padding(.vertical, 8)
                }
            }
        }
    }
    private var requests: some View {
        SWCard {
            Label("Requests", systemImage: "list.clipboard").font(.title2.bold())
            LoadFeedback(load: state.activityLoad, retryAfter: state.deadline("activity")) { await state.loadActivity() }
            if let rows = state.activity?.request_history, !rows.isEmpty {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NativeStatusCopy.label(row.status)).font(.headline)
                        Text("\(row.item_count) items · \(row.created_at.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Color.swMuted)
                    }
                }
            } else if state.activityLoad == .ready { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
        }
    }
    private var bookings: some View {
        SWCard {
            Label("Upcoming bookings", systemImage: "calendar").font(.title2.bold())
            if actions != nil { NavigationLink("Find a space", value: MemberRoute.spaces).frame(minHeight: 48) }
            LoadFeedback(load: state.bookingsLoad, lastUpdated: state.updated["bookings"], retryAfter: state.deadline("bookings")) { await state.loadBookings() }
            if state.bookingsLoad == .ready && state.bookings.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            ForEach(state.bookings, id: \.public_token) { booking in
                VStack(alignment: .leading, spacing: 8) {
                    if actions != nil { NavigationLink(booking.space_name, value: MemberRoute.booking(booking.public_token)).font(.headline).frame(minHeight: 48) }
                    else { Text(booking.space_name).font(.headline) }
                    Text(memberDate(booking.starts_at, timezone: booking.timezone))
                    Text(NativeStatusCopy.label(booking.status.value1.rawValue)).foregroundStyle(Color.swMuted)
                }.padding(.vertical, 8)
            }
            if state.bookingsHasMore { Button("Load more bookings") { Task { await state.loadBookings(more: true) } }.frame(minHeight: 48).disabled(state.bookingsLoad == .loading) }
        }
    }
    private var events: some View {
        SWCard {
            Label("Events", systemImage: "ticket").font(.title2.bold())
            LoadFeedback(load: state.eventsLoad, lastUpdated: state.updated["events"], retryAfter: state.deadline("events")) { await state.loadEvents() }
            if state.eventsLoad == .ready && state.events.isEmpty { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
            ForEach(state.events, id: \.public_token) { event in
                VStack(alignment: .leading, spacing: 8) {
                    if actions != nil { NavigationLink(event.title, value: MemberRoute.event(event.public_token)).font(.headline).frame(minHeight: 48) }
                    else { Text(event.title).font(.headline) }
                    Text(memberDate(event.starts_at, timezone: TimeZone.current.identifier)).foregroundStyle(Color.swMuted)
                }.padding(.vertical, 8)
            }
        }
    }
    private var registrations: some View {
        SWCard {
            Label("Event registrations", systemImage: "qrcode").font(.title2.bold())
            LoadFeedback(load: state.activityLoad, retryAfter: state.deadline("activity")) { await state.loadActivity() }
            if let rows = state.activity?.event_registrations, !rows.isEmpty {
                ForEach(rows, id: \.registration_id) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(row.event_title, value: MemberRoute.registration(row.registration_id)).font(.headline).frame(minHeight: 48).accessibilityIdentifier("registration-\(row.registration_id)")
                        Text(NativeStatusCopy.label(row.status)).foregroundStyle(Color.swMuted)
                        Text(row.starts_at.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Color.swMuted)
                    }
                }
            } else if state.activityLoad == .ready { Text("Nothing here yet.").foregroundStyle(Color.swMuted) }
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
            if paymentsAvailable { NavigationLink("Payments", value: MemberRoute.payments).frame(minHeight: 48).accessibilityIdentifier("payments-home-entry") }
            if state.activityLoad == .loading || state.activityLoad == .idle {
                LoadFeedback(load: state.activityLoad, retryAfter: state.deadline("activity")) { await state.loadActivity() }
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
    var retryAfter: Date?
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
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    Button((retryAfter ?? .distantPast) > tick.date ? CooldownCopy.retryButton(until: retryAfter ?? tick.date, now: tick.date) : "Try again") { Task { await retry() } }
                        .frame(minHeight: 48).disabled((retryAfter ?? .distantPast) > tick.date)
                }
            }
        case .ready: EmptyView()
        }
    }
}

struct InventoryList: View {
    @Bindable var state: MemberState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    var cart: RequestCartState? = nil
    var navigation: MemberNavigation? = nil
    var drafts: MemberActionDrafts? = nil
    @State private var localSelection: Int?
    private var selectedProduct: Int? { navigation?.inventorySelection ?? localSelection }
    var body: some View {
        GeometryReader { geometry in
            let split = sizeClass == .regular && geometry.size.width >= 850 && !textSize.isAccessibilitySize
            HStack(spacing: 0) {
                inventory(split: split).frame(maxWidth: split ? 440 : .infinity)
                if split {
                    Rectangle().fill(Color.swOutline).frame(width: 1)
                    if let selectedProduct {
                        InventoryDetail(repository: state.repository, id: selectedProduct, cart: cart, drafts: drafts) { await state.loadActivity() }.id(selectedProduct)
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
                } label: { Label(state.categories.first(where: { $0.slug == state.category })?.name ?? String(localized: "All categories"), systemImage: "line.3.horizontal.decrease.circle") }.frame(minHeight: 48)
                if case .failed = state.categoriesLoad {
                    LoadFeedback(load: state.categoriesLoad, retryAfter: state.deadline("categories")) { await state.loadCategories() }
                }
                LoadFeedback(load: state.inventoryLoad, lastUpdated: state.updated["inventory"], retryAfter: state.deadline("inventory")) { await state.loadInventory() }
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
                        Button { if let navigation { navigation.inventorySelection = product.id } else { localSelection = product.id } } label: { productRow(product) }
                            .buttonStyle(.plain).accessibilityIdentifier("product-\(product.id)")
                            .accessibilityAddTraits(selectedProduct == product.id ? .isSelected : [])
                    } else {
                        NavigationLink(value: MemberRoute.product(product.id)) { productRow(product) }
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
    guard let value = product.availability else { return String(localized: "Ask your makerspace about availability.") }
    if let count = value.count, value.mode == .exact_count { return String(localized: "\(count) available") }
    return value.label?.rawValue ?? String(localized: "Ask your makerspace about availability.")
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
    var cart: RequestCartState?
    var completed: () async -> Void
    @State private var state: MemberProductState
    @State private var reviewCart = false
    @State private var added = false
    init(repository: any MemberRepository, id: Int, cart: RequestCartState? = nil, drafts: MemberActionDrafts? = nil, completed: @escaping () async -> Void = {}) {
        self.repository = repository; self.id = id; self.cart = cart; self.completed = completed
        _state = State(initialValue: drafts?.product(id, repository: repository) ?? MemberProductState(id: id) { try await repository.product(id) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let product = state.product {
                    Text(product.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(availability(product)).foregroundStyle(Color.swMuted)
                    if let cart {
                        Button("Add to request") { cart.add(product); added = cart.lines.contains(where: { $0.id == product.id }) }.buttonStyle(SWPrimary()).disabled(cart.busy)
                        if added { Label("Added to your request", systemImage: "checkmark.circle").foregroundStyle(Color.swAccentInk) }
                        if let error = cart.error { SWError(message: error) }
                        Button("Review your request") { reviewCart = true }.frame(minHeight: 48).accessibilityIdentifier("review-request")
                    }
                    SWCard { Text("About this item").font(.title2.bold()); Text(product.description) }
                    SWCard { Text("Borrowing terms").font(.title2.bold()); Text(product.borrowing_terms.isEmpty ? "Ask your makerspace about borrowing this item." : product.borrowing_terms) }
                } else if let error = state.error {
                    SWCard { LoadFeedback(load: .failed(error), retryAfter: state.retryAfter) { await state.load() } }
                } else { ProgressView("Loading item…") }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Item details").task { await state.load() }
            .sheet(isPresented: $reviewCart) {
                if let cart { RequestCartView(state: cart, isDemo: repository.isDemo, completed: completed) }
            }
    }
}

struct MemberInbox: View {
    @Bindable var state: MemberState
    var paymentsAvailable = false
    var openLink: ((String) -> Void)? = nil
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Messages", selection: $state.unreadOnly) { Text("All").tag(false); Text("Unread").tag(true) }.pickerStyle(.segmented)
                    .onChange(of: state.unreadOnly) { _, _ in Task { await state.loadInbox() } }
                Button("Mark all as read") { Task { await state.markAllRead() } }.frame(minHeight: 48).disabled(state.inboxMutating)
                LoadFeedback(load: state.inboxLoad, lastUpdated: state.updated["inbox"], retryAfter: state.deadline("inbox")) { await state.loadInbox() }
                if state.inboxLoad == .ready && state.messages.isEmpty { SWCard { Text("Nothing here yet.").foregroundStyle(Color.swMuted) } }
                ForEach(state.messages, id: \.id) { message in
                    SWCard {
                        HStack { Text(message.title).font(.headline); Spacer(); if message.read_at == nil { Label("Unread", systemImage: "circle.fill").font(.caption).foregroundStyle(Color.swAccentInk) } }
                        Text(message.summary).foregroundStyle(Color.swMuted)
                        Text(message.created_at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.swMuted)
                        if let openLink, !message.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Open update") { openLink(message.link) }.frame(minHeight: 48).accessibilityIdentifier("open-inbox-update-\(message.id)")
                        }
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
                    LoadFeedback(load: state.cardLoad, retryAfter: state.deadline("card")) { await state.loadCard() }
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
