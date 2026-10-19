import SwiftUI
import SpaceWorksAPI

/// A server number with its label. Numbers use tabular digits in accent ink.
struct StatTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value).brandFont(.title2, weight: .semibold).monospacedDigit().foregroundStyle(Color.swAccentInk)
            Text(label).brandFont(.subheadline).foregroundStyle(Color.swMuted)
        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(12)
            .background(Color.swPanel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.swLine))
            .accessibilityElement(children: .combine)
    }
}

/// Horizontal bars for one server series, each value written out; never an inferred aggregate.
struct UsageBars: View {
    let title: String
    let series: UsageSeries
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brandFont(.headline)
            if series.points.isEmpty {
                Text("No activity in this period yet.").foregroundStyle(Color.swMuted)
            } else {
                let top = max(series.points.map(\.amount).max() ?? 0, 1)
                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(verbatim: point.label); Spacer(); Text(verbatim: [point.value, series.unit].filter { !$0.isEmpty }.joined(separator: " ")).monospacedDigit() }
                            .brandFont(.subheadline)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.swAccentSoft)
                                Capsule().fill(Color.swAccentInk).frame(width: geometry.size.width * max(0, min(1, point.amount / top)))
                            }
                        }.frame(height: 8).accessibilityHidden(true)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct UsageSection: View {
    let state: InsightsState
    @Environment(\.dynamicTypeSize) private var textSize
    private var columns: [GridItem] { textSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140), spacing: 12)] }
    var body: some View {
        SWCard {
            Text("Your activity").brandFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            switch state.usage {
            case .idle, .loading: ProgressView("Loading activity").frame(minHeight: 48)
            case .failed(let message):
                SWError(message: message)
                Button("Refresh activity") { Task { await state.refreshUsage() } }.frame(minHeight: 48)
            case .ready(let usage):
                if !usage.usage_available && usage.payments == nil {
                    Text("Activity details aren't available for this makerspace.").foregroundStyle(Color.swMuted)
                }
                if let loans = usage.loans {
                    Text("Loans").brandFont(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        StatTile(label: String(localized: "Borrowed"), value: "\(loans.count)")
                        StatTile(label: String(localized: "Returned"), value: "\(loans.returned_count)")
                        StatTile(label: String(localized: "Out now"), value: "\(loans.currently_out)")
                    }
                    UsageBars(title: String(localized: "By month"), series: .from(loans.monthly))
                }
                if let machines = usage.machines {
                    Text("Machine time").brandFont(.headline)
                    StatTile(label: String(localized: "Hours"), value: machines.hours)
                    UsageBars(title: String(localized: "By month"), series: .from(machines.monthly))
                    UsageBars(title: String(localized: "Most used machines"), series: .from(machines.top_machines))
                }
                if usage.bookings != nil || usage.events != nil {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        if let bookings = usage.bookings { StatTile(label: String(localized: "Bookings"), value: "\(bookings.count)") }
                        if let events = usage.events { StatTile(label: String(localized: "Events attended"), value: "\(events.attended_count)") }
                    }
                    if let bookings = usage.bookings { UsageBars(title: String(localized: "By month"), series: .from(bookings.monthly)) }
                }
                if let payments = usage.payments {
                    Text("Payments").brandFont(.headline)
                    let currencies = Set(payments.paid_by_currency.additionalProperties.keys).union(payments.outstanding_by_currency.additionalProperties.keys).sorted()
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(currencies, id: \.self) { currency in
                            if let paid = payments.paid_by_currency.additionalProperties[currency] {
                                StatTile(label: String(localized: "Paid"), value: currency.uppercased() + " " + paid)
                            }
                            if let outstanding = payments.outstanding_by_currency.additionalProperties[currency] {
                                StatTile(label: String(localized: "Outstanding"), value: currency.uppercased() + " " + outstanding)
                            }
                        }
                    }
                }
            }
        }.accessibilityIdentifier("member-usage")
            .task { if state.usage == .idle { await state.refreshUsage() } }
    }
}

struct StaffGlanceSection: View {
    let state: InsightsState
    @Environment(\.dynamicTypeSize) private var textSize
    private var columns: [GridItem] { textSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 160), spacing: 12)] }
    var body: some View {
        SWCard {
            Text("Today at a glance").brandFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            switch state.dashboard {
            case .idle, .loading: ProgressView().frame(minHeight: 48)
            case .failed(let message):
                SWError(message: message)
                Button("Refresh dashboard") { Task { await state.refreshDashboard() } }.frame(minHeight: 48)
            case .ready(let glance):
                if glance.counters.isEmpty && glance.queue.isEmpty && glance.widgets.isEmpty && glance.outstanding.isEmpty {
                    Text("Nothing needs your attention right now.").foregroundStyle(Color.swMuted)
                }
                if !glance.queue.isEmpty {
                    Text("Handover queue").brandFont(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(glance.queue, id: \.key) { StatTile(label: StaffGlance.label($0.key), value: "\($0.value)") }
                    }
                }
                if !glance.counters.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(glance.counters, id: \.key) { StatTile(label: StaffGlance.label($0.key), value: "\($0.value)") }
                    }
                }
                if !glance.outstanding.isEmpty {
                    Text("Outstanding payments").brandFont(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(glance.outstanding, id: \.currency) { StatTile(label: String(localized: "Outstanding"), value: $0.currency + " " + $0.amount) }
                    }
                }
                if !glance.widgets.isEmpty {
                    Text("Reports").brandFont(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(glance.widgets, id: \.key) { widget in
                            if let headline = widget.headline { StatTile(label: widget.title, value: headline) }
                            else { Text(verbatim: widget.title).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading) }
                        }
                    }
                }
            }
        }.accessibilityIdentifier("staff-glance")
            .task { if state.dashboard == .idle { await state.refreshDashboard() } }
    }
}

struct MessagingConsentView: View {
    let state: InsightsState
    var openAccount: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Text and WhatsApp messages").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                Text("Choose whether this makerspace can reach you by text message or WhatsApp. App notifications and email are set separately.")
                    .foregroundStyle(Color.swMuted)
                if let error = state.consentError { SWError(message: error) }
                switch state.messaging {
                case .idle, .loading: ProgressView().frame(minHeight: 48)
                case .failed(let message):
                    SWError(message: message)
                    Button("Try again") { Task { await state.refreshMessaging() } }.frame(minHeight: 48)
                case .ready(let consent):
                    channel(.sms, title: String(localized: "Text messages (SMS)"), value: consent.sms)
                    channel(.whatsapp, title: String(localized: "WhatsApp"), value: consent.whatsapp)
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Color.swBg).navigationTitle("Messages").navigationBarTitleDisplayMode(.inline)
            .task { await state.refreshMessaging() }
            .accessibilityIdentifier("messaging-consent")
    }
    private func channel(_ key: Components.Schemas.Channel06eEnum, title: String, value: Components.Schemas.MessagingChannel) -> some View {
        SWCard {
            Toggle(isOn: Binding(get: { value.consented }, set: { optIn in Task { await state.setConsent(key, optIn: optIn) } })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).brandFont(.headline)
                    Text(value.consented ? "On" : "Off").brandFont(.subheadline).foregroundStyle(Color.swMuted)
                }
            }.frame(minHeight: 48).disabled(state.consentBusy != nil || (!value.consented && !InsightsState.canOptIn(value)))
                .accessibilityIdentifier("messaging-\(key.rawValue)")
            if !value.available { Text("This makerspace doesn't send these messages.").foregroundStyle(Color.swMuted) }
            else if value.suppressed { Text("Messages to this number are paused after a STOP reply. Contact your makerspace to resume them.").foregroundStyle(Color.swMuted) }
            else if !value.phone_verified {
                Text("Verify your phone number in Account and security before turning this on.").foregroundStyle(Color.swMuted)
                if let openAccount { Button("Open Account and security", action: openAccount).frame(minHeight: 48) }
            } else if !value.phone_masked.isEmpty {
                Text("Messages go to \(value.phone_masked).").foregroundStyle(Color.swMuted)
            }
        }
    }
}
