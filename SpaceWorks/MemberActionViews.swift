import SwiftUI
import SpaceWorksAPI

struct RequestCartView: View {
    @Bindable var state: RequestCartState
    let isDemo: Bool
    let completed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isDemo { Text("Demo mode · no real request is submitted").font(.caption.bold()).foregroundStyle(Color.swMuted) }
                    if let receipt = state.receipt {
                        SWCard {
                            Label("Request received", systemImage: "checkmark.circle").font(.largeTitle.bold())
                            Text(receipt.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.title2)
                            Text("Your makerspace will review your request and confirm collection and due dates.").foregroundStyle(Color.swMuted)
                            Text("Request reference").font(.headline)
                            Text(receipt.public_token).font(.body.monospaced()).textSelection(.enabled)
                            Button("Done") { dismiss() }.buttonStyle(SWPrimary())
                        }
                    } else {
                        Text("Review your request").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("Check the items and quantities. Your makerspace confirms availability and borrowing terms.").foregroundStyle(Color.swMuted)
                        if state.lines.isEmpty { SWCard { Text("Your request is empty."); Text("Add an item from inventory to get started.").foregroundStyle(Color.swMuted) } }
                        ForEach(state.lines) { line in
                            SWCard {
                                Text(line.product.name).font(.headline)
                                Stepper("Quantity: \(line.quantity)", value: Binding(get: { state.lines.first(where: { $0.id == line.id })?.quantity ?? 1 }, set: { state.quantity($0, for: line.id) }), in: 1...99)
                                    .frame(minHeight: 48)
                                Button("Remove item", role: .destructive) { state.quantity(0, for: line.id) }.frame(minHeight: 48)
                            }
                        }
                        SWCard {
                            Text("What are you making? (optional)").font(.headline)
                            TextField("Tell your makerspace about your project", text: $state.purpose, axis: .vertical)
                                .lineLimit(3...6).padding(14).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("request-purpose")
                            Text("Up to 500 characters. Don't include sensitive information.").font(.caption).foregroundStyle(Color.swMuted)
                            if let error = state.error { SWError(message: error) }
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                if let deadline = state.retryAfter, tick.date < deadline { Text("Try again in \(max(1, Int(ceil(deadline.timeIntervalSince(tick.date)))))s.").foregroundStyle(Color.swMuted) }
                                Button(state.busy ? "Submitting…" : "Submit request") {
                                    Task { await state.submit(); if state.receipt != nil { await completed() } }
                                }.buttonStyle(SWPrimary()).disabled(state.busy || state.lines.isEmpty || (state.retryAfter ?? .distantPast) > tick.date)
                                    .accessibilityIdentifier("submit-request")
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity).disabled(state.busy)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively).accessibilityIdentifier("request-review-scroll").requestScrollDiagnostics()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.frame(minHeight: 48).disabled(state.busy) } }
        }.interactiveDismissDisabled(state.busy)
    }
}

struct RenewLoanView: View {
    let loan: Components.Schemas.MemberLoanActivity
    let repository: any MemberActionsRepository
    let isDemo: Bool
    let completed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var result: Components.Schemas.LoanRenewal?
    @State private var error: String?
    @State private var busy = false
    @State private var retryAfter: Date?
    var body: some View {
        NavigationStack {
            ScrollView {
                SWCard {
                    if isDemo { Text("Demo mode · no real loan is changed").font(.caption.bold()).foregroundStyle(Color.swMuted) }
                    Text(result == nil ? "Renew this loan?" : "Loan renewed").font(.largeTitle.bold())
                    Text(loan.label).font(.title2.bold())
                    if let result {
                        Text("New due date").font(.headline)
                        Text(result.return_due_at.formatted(date: .abbreviated, time: .shortened))
                        Button("Done") { dismiss() }.buttonStyle(SWPrimary())
                    } else {
                        if let due = loan.due_at { Text("Currently due \(due.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(Color.swMuted) }
                        Text("Your makerspace checks its renewal policy. A renewal is confirmed only when a new due date is returned.").foregroundStyle(Color.swMuted)
                        if let error { SWError(message: error) }
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            Button(busy ? "Checking…" : "Confirm renewal") { Task { await renew() } }.buttonStyle(SWPrimary())
                                .disabled(busy || (retryAfter ?? .distantPast) > tick.date)
                        }
                    }
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background(Color.swBg).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48).disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
    private func renew() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { result = try await repository.renew(request: loan.request_id); await completed() }
        catch { self.error = APIError.display(error); retryAfter = APIError.retryDeadline(error) }
    }
}
