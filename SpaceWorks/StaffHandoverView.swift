import SwiftUI
import SpaceWorksAPI
import UIKit

struct StaffHandoverView: View {
    @State var state: StaffHandoverState
    @State private var scanner: ScanKind?
    @State private var camera = false
    @State private var cameraMessage: String?
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss
    private enum ScanKind: String, Identifiable { case box, equipment; var id: String { rawValue } }
    private var directIssue: Bool { if case .directIssue = state.mode { return true }; return false }
    private var currentTitle: String { state.steps[min(state.step, state.steps.count - 1)] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Step \(state.step + 1) of \(state.steps.count)").brandFont(.subheadline).foregroundStyle(Color.swMuted)
                ProgressView(value: Double(state.step + 1), total: Double(state.steps.count)).tint(Color.swAccentInk).accessibilityLabel("Handover progress")
                Text(currentTitle).brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                if state.isDemo { Label("Demo handover · no live equipment changes", systemImage: "info.circle").foregroundStyle(Color.swMuted) }
                if let error = state.error { SWError(message: error).accessibilityIdentifier("staff-handover-error") }
                if let notice = state.notice { Label(notice, systemImage: "info.circle").foregroundStyle(Color.swMuted) }
                if state.busy { ProgressView("Working…") }
                if !state.parent.isActive {
                    SWError(message: state.parent.error ?? String(localized: "Your access changed. Return to your makerspace before continuing."))
                    Button("Close") { dismiss() }.buttonStyle(SWPrimary())
                } else if let receipt = state.receipt {
                    SWCard {
                        Label(receipt, systemImage: "checkmark.circle").brandFont(.title2, weight: .bold).accessibilityIdentifier("staff-handover-recorded")
                        if let evidence = state.evidenceID { Text("Evidence photo #\(evidence)") }
                        if !state.remark.isEmpty { Text(state.remark) }
                        Text("This summary reflects the recorded handover. Refresh the loan to see its latest status.").foregroundStyle(Color.swMuted)
                    }
                    Button("Done") { dismiss() }.buttonStyle(SWPrimary())
                } else if state.needsReload {
                    Text("Check the latest request before starting another handover. A failed response may need reconciliation.").foregroundStyle(Color.swMuted)
                    Button("Close and refresh") { Task { await state.parent.loadQueue(); await state.parent.loadDirect(); dismiss() } }.buttonStyle(SWPrimary())
                } else {
                    stepContent.disabled(state.busy)
                    if state.step > 0 { Button("Back") { state.step -= 1 }.frame(minHeight: 48).disabled(state.busy || state.assignmentRecorded) }
                    if state.step < state.reviewStep {
                        Button("Next") {
                            state.step += 1
                            if state.step == state.reviewStep { Task { await state.prepareKits() } }
                        }.buttonStyle(SWPrimary()).disabled(!canAdvance || state.busy).accessibilityIdentifier("staff-handover-next")
                    } else {
                        Button(state.mode.isReturn ? "Confirm return" : "Confirm handout") { confirm = true }
                            .buttonStyle(SWPrimary()).disabled(!state.ready).accessibilityIdentifier("staff-handover-confirm")
                    }
                }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle(state.mode.title).navigationBarTitleDisplayMode(.inline)
            .nativeFeedback(state.feedback)
            .interactiveDismissDisabled(state.busy)
            .navigationBarBackButtonHidden(state.busy)
            .task {
                if directIssue { await state.loadBorrowers(); await state.loadProducts() }
            }
            .sheet(item: $scanner) { kind in
                NativeQRScanner(title: kind == .box ? String(localized: "Check handover code") : String(localized: "Add equipment")) { value in
                    scanner = nil; Task { await state.scan(value, box: kind == .box) }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                NativeEvidenceCamera(onPhoto: { result in
                    camera = false
                    switch result { case .success(let photo): state.setPhoto(photo); case .failure: cameraMessage = String(localized: "This photo could not be prepared. Take another photo.") }
                }, onCancel: { camera = false }).ignoresSafeArea()
            }
            .confirmationDialog(state.mode.isReturn ? "Record this return?" : "Record this handout?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Record handover") { Task { await state.confirm() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Check the borrower, equipment, counts, and evidence before recording the handover.") }
    }
    @ViewBuilder private var stepContent: some View {
        if state.step == state.reviewStep { review }
        else if directIssue && state.step == 0 { borrowers }
        else if directIssue || (!state.mode.isReturn && state.step == 2) { equipment }
        else if !state.mode.isReturn && state.step == 1 { borrowerCheck }
        else if state.mode.isReturn && state.step == 1 { returnedItems }
        else { container }
    }
    private var canAdvance: Bool {
        if directIssue && state.step == 0 { return state.members.contains { $0.user_id == state.borrowerID } }
        if directIssue || (!state.mode.isReturn && state.step == 2) || (state.mode.isReturn && state.step == 1) { return state.itemsReady }
        if !state.mode.isReturn && state.step == 1 { return state.borrowerChecked }
        return !state.requiresBox || !state.boxCode.isEmpty
    }
    private var container: some View {
        SWCard {
            Text(state.mode.loan == nil ? "Check the container" : "Check the loan code").brandFont(.headline)
            Text(state.requiresBox ? "Scan the code attached to this handover. The server will verify it belongs to this makerspace." : "This loan does not require a return scan.").foregroundStyle(Color.swMuted)
            if state.requiresBox { Button(state.boxCode.isEmpty ? "Scan handover code" : "Scan another code") { scanner = .box }.frame(minHeight: 48) }
            if !state.boxLabel.isEmpty { Label(state.boxLabel, systemImage: "checkmark.circle") }
        }
    }
    private var borrowerCheck: some View {
        SWCard {
            if let row = state.mode.request {
                Text(row.requester_display.isEmpty ? row.requester_username : row.requester_display).brandFont(.title2, weight: .bold)
                Text("Request #\(row.id)").foregroundStyle(Color.swMuted)
                Text("Check the borrower's membership card or approved identification before handing over the equipment.").foregroundStyle(Color.swMuted)
                Toggle("I checked the borrower against this request", isOn: $state.borrowerChecked).frame(minHeight: 48).accessibilityIdentifier("staff-borrower-checked")
            }
        }
    }
    private var borrowers: some View {
        SWCard {
            Text("Choose an eligible borrower").brandFont(.headline)
            Text("These people are supplied by this makerspace. Selecting a person does not create a sign-in account.").foregroundStyle(Color.swMuted)
            Picker("Borrower", selection: $state.borrowerID) {
                Text("Choose a borrower").tag(Optional<Int>.none)
                ForEach(state.members, id: \.user_id) { member in Text(member.display_name.isEmpty ? member.username : member.display_name).tag(Optional(member.user_id)) }
            }.pickerStyle(.menu).frame(minHeight: 48).accessibilityIdentifier("staff-borrower")
            if state.membersNext != nil { Button("Load more borrowers") { Task { await state.loadBorrowers(more: true) } }.frame(minHeight: 48) }
            if state.members.isEmpty && !state.busy { Button("Reload borrowers") { Task { await state.loadBorrowers() } }.frame(minHeight: 48) }
        }
    }
    private var equipment: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let row = state.mode.request {
                ForEach(row.items, id: \.id) { item in SWCard { Text(item.product_name).brandFont(.headline); Text("Accepted: \(item.accepted_quantity)"); if item.requires_asset_qr { Text("Scan each individual asset.").foregroundStyle(Color.swMuted) } } }
            } else {
                ForEach(state.products.filter { $0.is_archived != true && ($0.available_quantity ?? 0) > 0 && $0.tracking_mode?.rawValue != "individual" }, id: \.id) { item in
                    SWCard {
                        Text(item.name).brandFont(.headline)
                        Stepper("Quantity: \(state.bulkQuantities[item.id] ?? 0)", value: Binding(get: { state.bulkQuantities[item.id] ?? 0 }, set: { state.bulkQuantities[item.id] = $0 }), in: 0...max(0, item.available_quantity ?? 0)).frame(minHeight: 48).accessibilityLabel("Quantity for \(item.name)").accessibilityValue("\(state.bulkQuantities[item.id] ?? 0)")
                    }
                }
                if state.productsNext != nil { Button("Load more equipment") { Task { await state.loadProducts(more: true) } }.frame(minHeight: 48) }
                if state.products.isEmpty && !state.busy { Button("Reload equipment") { Task { await state.loadProducts() } }.frame(minHeight: 48) }
            }
            Button("Scan equipment code") { scanner = .equipment }.frame(minHeight: 48).disabled(state.busy)
            Text("\(state.scans.count) equipment codes checked").brandFont(.subheadline).foregroundStyle(Color.swMuted)
            if !state.duplicateProducts.isEmpty { SWError(message: String(localized: "This equipment is both scanned and selected by quantity. Remove one selection before continuing.")) }
            ForEach(state.scans.keys.sorted(), id: \.self) { payload in
                HStack(alignment: .top) {
                    Text(state.scans[payload]?.target.additionalProperties["label"]?.value as? String ?? String(localized: "Equipment code added")).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Remove") { state.removeScan(payload) }.frame(minHeight: 48).accessibilityLabel("Remove \(state.scans[payload]?.target.additionalProperties["label"]?.value as? String ?? "equipment code")")
                }
            }
        }
    }
    private var returnedItems: some View {
        ForEach(state.returns.indices, id: \.self) { index in
            SWCard {
                Text(state.returns[index].label).brandFont(.headline)
                Text("Remaining: \(state.returns[index].remaining)").foregroundStyle(Color.swMuted)
                if !state.returns[index].metadataValid { SWError(message: String(localized: "Asset details are unavailable. Refresh this loan before recording a return.")) }
                else if state.returns[index].assets.isEmpty {
                    countStepper("Returned", index: index, keyPath: \.returned)
                    countStepper("Damaged", index: index, keyPath: \.damaged)
                    countStepper("Missing", index: index, keyPath: \.missing)
                } else {
                    ForEach(state.returns[index].assets, id: \.id) { asset in
                        Picker(asset.label, selection: Binding(get: { state.returns[index].outcomes[asset.id] ?? "pending" }, set: { state.returns[index].setOutcome(assetID: asset.id, value: $0) })) {
                            Text("Not returned now").tag("pending"); Text("Returned").tag("returned"); Text("Damaged").tag("damaged"); Text("Missing").tag("missing")
                        }.pickerStyle(.menu).frame(minHeight: 48)
                    }
                }
                if !state.returns[index].valid { Text("Check that these counts do not exceed the remaining quantity.").foregroundStyle(Color.swDanger) }
            }
        }
    }
    private func countStepper(_ title: String, index: Int, keyPath: WritableKeyPath<StaffReturnDraft, Int>) -> some View {
        Stepper("\(title): \(state.returns[index][keyPath: keyPath])", value: Binding(get: { state.returns[index][keyPath: keyPath] }, set: { state.returns[index][keyPath: keyPath] = $0 }), in: 0...max(0, state.returns[index].remaining)).frame(minHeight: 48).accessibilityLabel("\(title) \(state.returns[index].label)").accessibilityValue("\(state.returns[index][keyPath: keyPath])")
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 24) {
            SWCard {
                Text("Evidence photo").brandFont(.headline)
                Text("Photograph the equipment and its condition. Avoid faces or unrelated personal information.").foregroundStyle(Color.swMuted)
                if let photo = state.photo, let image = UIImage(data: photo) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Evidence photo preview") }
                Button(state.photo == nil ? "Take evidence photo" : "Retake photo") { Task { await prepareCamera() } }.frame(minHeight: 48).disabled(state.busy)
                #if DEBUG
                if state.isDemo { Button("Use sample evidence photo") { samplePhoto() }.frame(minHeight: 48).accessibilityIdentifier("staff-sample-photo") }
                #endif
                if let cameraMessage { Text(cameraMessage).foregroundStyle(Color.swMuted) }
                if let evidence = state.evidenceID { Label("Photo uploaded · #\(evidence)", systemImage: "checkmark.circle") }
                else if state.photo != nil { Button("Upload evidence photo") { Task { await state.uploadPhoto() } }.frame(minHeight: 48).disabled(state.busy).accessibilityIdentifier("staff-upload-photo") }
            }
            if state.needsKits {
                SWCard {
                    Text("Kit checklist").brandFont(.headline)
                    Text("Count each component. Enter zero for a missing component.").foregroundStyle(Color.swMuted)
                    if !state.kitsReady { Button("Load kit checklist") { Task { await state.prepareKits() } }.frame(minHeight: 48).disabled(state.busy) }
                    ForEach(state.kits, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(item.owner_label) · \(item.label)")
                            if state.kitCounts[item.key] == nil { Button("Start count") { state.kitCounts[item.key] = 0 }.frame(minHeight: 48).accessibilityLabel("Start count for \(item.owner_label), \(item.label)") }
                            else { Stepper("Present: \(state.kitCounts[item.key] ?? 0) of \(item.quantity)", value: Binding(get: { state.kitCounts[item.key] ?? 0 }, set: { state.kitCounts[item.key] = $0 }), in: 0...max(0, item.quantity)).frame(minHeight: 48).accessibilityLabel("Present \(item.owner_label), \(item.label)").accessibilityValue("\(state.kitCounts[item.key] ?? 0) of \(item.quantity)") }
                        }
                    }
                }
            }
            Text(state.mode.isReturn ? "Return remark (required)" : "Issue remark (optional)").brandFont(.headline)
            TextField("Describe the equipment condition", text: $state.remark, axis: .vertical).lineLimit(3...8).modifier(StaffInput()).accessibilityIdentifier("staff-handover-remark")
            if state.mode.isReturn { ForEach(state.returns, id: \.id) { item in Text("\(item.label): \(item.returned) returned, \(item.damaged) damaged, \(item.missing) missing").foregroundStyle(Color.swMuted) } }
            Text("Confirming records this handover. Review the details before continuing.").foregroundStyle(Color.swMuted)
        }
    }
    private func prepareCamera() async {
        do {
            switch try await NativeCameraAccess.request() {
            case .ready: cameraMessage = nil; camera = true
            case .denied: cameraMessage = String(localized: "Allow Camera in Settings to take an evidence photo.")
            case .restricted: cameraMessage = String(localized: "Camera access is restricted on this device. Ask an administrator or use another device.")
            case .unavailable: cameraMessage = String(localized: "This device has no available camera. Use a device with a camera to record this handover.")
            }
        } catch { cameraMessage = String(localized: "Camera request cancelled.") }
    }
    #if DEBUG
    private func samplePhoto() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            "DEMO EVIDENCE · SAMPLE DATA".draw(at: CGPoint(x: 40, y: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        if let data = try? NativePhotoPreparation.jpeg(from: image) { state.setPhoto(data) }
    }
    #endif
}
