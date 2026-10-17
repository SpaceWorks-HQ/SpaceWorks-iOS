import Foundation
import CoreFoundation
import Observation
import SpaceWorksAPI

enum StaffMetadata {
    static func positiveID(_ value: Any?) -> Int? {
        guard let value, let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), let id = value as? Int, id > 0 else { return nil }
        return id
    }
    static func remaining(issued: Int, returned: Int, damaged: Int, missing: Int) -> Int? {
        guard issued >= 0 else { return nil }
        var remaining = issued
        for count in [returned, damaged, missing] {
            guard count >= 0, count <= remaining else { return nil }
            remaining -= count
        }
        return remaining
    }
}

enum StaffHandoverMode {
    case issue(Components.Schemas.AdminRequest), returnRequest(Components.Schemas.AdminRequest)
    case directIssue, directReturn(Components.Schemas.DirectLoan)
    var isReturn: Bool { switch self { case .returnRequest, .directReturn: return true; default: return false } }
    var request: Components.Schemas.AdminRequest? { switch self { case .issue(let row), .returnRequest(let row): return row; default: return nil } }
    var loan: Components.Schemas.DirectLoan? { if case .directReturn(let row) = self { return row }; return nil }
    var isDirect: Bool { switch self { case .directIssue, .directReturn: return true; default: return false } }
    var title: String { switch self { case .issue: return String(localized: "Issue equipment"); case .returnRequest, .directReturn: return String(localized: "Return equipment"); case .directIssue: return String(localized: "Direct handout") } }
}

/// Editable return counts are UI state. Only generated ReturnItemResolution is sent to the API.
struct StaffReturnDraft {
    let id: Int
    let label: String
    let remaining: Int
    let assets: [(id: Int, label: String)]
    var metadataValid = true
    var returned: Int
    var damaged = 0
    var missing = 0
    var outcomes: [Int: String] = [:]
    var valid: Bool {
        metadataValid && remaining >= 0 && [returned, damaged, missing].allSatisfy { $0 >= 0 } &&
            returned <= remaining && damaged <= remaining - returned && missing <= remaining - returned - damaged
    }
    var body: Components.Schemas.ReturnItemResolution {
        let values: [Components.Schemas.ReturnAssetResolution]? = assets.isEmpty ? nil : assets.compactMap { asset in
            guard let raw = outcomes[asset.id], let outcome = Components.Schemas.ReturnAssetResolutionOutcomeEnum(rawValue: raw) else { return nil }
            return .init(asset_id: asset.id, outcome: outcome)
        }
        return .init(item_id: id, returned: returned, damaged: damaged, missing: missing, assets: values)
    }
    mutating func setOutcome(assetID: Int, value: String) {
        guard assets.contains(where: { $0.id == assetID }) else { return }
        outcomes[assetID] = value == "pending" ? nil : value
        returned = outcomes.values.filter { $0 == "returned" }.count
        damaged = outcomes.values.filter { $0 == "damaged" }.count
        missing = outcomes.values.filter { $0 == "missing" }.count
    }
}

@MainActor @Observable
final class StaffHandoverState {
    private(set) var mode: StaffHandoverMode
    let parent: StaffState
    var step = 0
    var borrowerID: Int?
    var borrowerChecked = false
    var remark = ""
    var bulkQuantities: [Int: Int] = [:] { didSet { kitsReady = false; kitCounts = [:] } }
    var returns: [StaffReturnDraft] = [] { didSet { kitsReady = false; kitCounts = [:] } }
    var kitCounts: [String: Int] = [:]
    private(set) var members: [Components.Schemas.DirectLoanMember] = []
    private(set) var products: [Components.Schemas.InventoryProductAdmin] = []
    private(set) var membersNext: Int?
    private(set) var productsNext: Int?
    private(set) var boxCode = ""
    private(set) var boxLabel = ""
    private(set) var scans: [String: Components.Schemas.QrResolveResult] = [:]
    private(set) var kits: [Components.Schemas.KitExpectation] = []
    private(set) var kitsReady = false
    private(set) var photo: Data?
    private(set) var evidenceID: Int?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var receipt: String?
    private(set) var assignmentRecorded = false
    private(set) var needsReload = false
    private var active = true
    private var generation = 0
    private let upload: @Sendable (Components.Schemas.EvidenceUrlResponse, Data) async throws -> Void
    init(parent: StaffState, mode: StaffHandoverMode,
         upload: @escaping @Sendable (Components.Schemas.EvidenceUrlResponse, Data) async throws -> Void = StaffEvidenceUpload.send) {
        self.parent = parent; self.mode = mode; self.upload = upload
        if let row = mode.request, mode.isReturn {
            returns = row.items.map { item in
                let assets: [(id: Int, label: String)] = item.issued_assets.compactMap { value in
                    guard let data = try? JSONEncoder().encode(value),
                          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                          let id = StaffMetadata.positiveID(object["asset_id"]) else { return nil }
                    return (id, object["asset_tag"] as? String ?? String(localized: "Asset #\(id)"))
                }
                let remaining = StaffMetadata.remaining(issued: item.issued_quantity, returned: item.returned_quantity, damaged: item.damaged_quantity, missing: item.missing_quantity)
                let metadataValid = remaining != nil && (!item.requires_asset_qr || remaining == 0 || (!assets.isEmpty && assets.count == item.issued_assets.count && Set(assets.map(\.id)).count == assets.count))
                return StaffReturnDraft(id: item.id, label: item.product_name, remaining: remaining ?? 0, assets: assets,
                    metadataValid: metadataValid, returned: 0)
            }
        } else if let row = mode.loan {
            returns = row.return_items.map { item in
                let assets = item.assets.map { (id: $0.asset_id, label: $0.asset_tag) }
                return StaffReturnDraft(id: item.item_id, label: item.product_name, remaining: item.remaining_quantity,
                    assets: assets, metadataValid: item.remaining_quantity >= 0 && assets.allSatisfy({ $0.id > 0 }) && Set(assets.map(\.id)).count == assets.count && (item.tracking_mode != "individual" || item.remaining_quantity == 0 || !assets.isEmpty), returned: 0)
            }
        }
        parent.registerChild { [weak self] in self?.invalidate() }
    }
    var isDemo: Bool { parent.isDemo }
    var canRequest: Bool { active && parent.canRequest && !busy }
    var steps: [String] {
        if case .directIssue = mode { return ["Borrower", "Equipment", "Photo and review", "Receipt"] }
        if mode.isReturn { return ["Container", "Returned items", "Photo and review", "Receipt"] }
        return ["Container", "Borrower", "Equipment", "Photo and review", "Receipt"]
    }
    var reviewStep: Int { steps.count - 2 }
    var requiresBox: Bool { !mode.isDirect || (mode.loan?.return_scan_required ?? false) }
    var needsKits: Bool { parent.features.contains("loans.kit_checklist") || mode.request?.has_kit_checklist == true || mode.loan?.has_kit_checklist == true }
    var selectedItems: [Components.Schemas.DirectLoanItem] {
        products.filter { (bulkQuantities[$0.id] ?? 0) > 0 }.map { .init(product_id: $0.id, quantity: bulkQuantities[$0.id] ?? 0) }
    }
    var duplicateProducts: Set<Int> {
        Set(scans.values.compactMap { result -> Int? in
            let product = StaffMetadata.positiveID(result.target.additionalProperties["product_id"]?.value)
                ?? (result.qr.target_type.rawValue == "product" ? result.qr.target_id : nil)
            guard let product, (bulkQuantities[product] ?? 0) > 0 else { return nil }; return product
        })
    }
    var kitBody: [Components.Schemas.KitCount]? {
        needsKits ? kits.map { .init(key: $0.key, present: kitCounts[$0.key] ?? 0) } : nil
    }
    var itemsReady: Bool {
        if mode.isReturn { return returns.allSatisfy(\.valid) && returns.contains { $0.returned > 0 || $0.damaged > 0 || $0.missing > 0 } }
        if let row = mode.request {
            return row.items.contains(where: { $0.accepted_quantity > 0 }) && row.items.filter(\.requires_asset_qr).allSatisfy { item in
                scans.values.filter { StaffMetadata.positiveID($0.target.additionalProperties["product_id"]?.value) == item.product_id }.count == item.accepted_quantity
            }
        }
        let validBulk = bulkQuantities.allSatisfy { id, quantity in
            guard let product = products.first(where: { $0.id == id }) else { return quantity == 0 }
            return quantity >= 0 && quantity <= (product.available_quantity ?? 0) && product.tracking_mode?.rawValue != "individual" && product.is_archived != true
        }
        return validBulk && duplicateProducts.isEmpty && (!selectedItems.isEmpty || !scans.isEmpty)
    }
    var ready: Bool {
        guard canRequest, !needsReload, mode.request?.makerspace_id == nil || mode.request?.makerspace_id == parent.makerspaceID,
              evidenceID != nil, itemsReady, !requiresBox || !boxCode.isEmpty,
              !needsKits || (kitsReady && kits.allSatisfy({ $0.quantity >= 0 && (0...$0.quantity).contains(kitCounts[$0.key] ?? -1) })) else { return false }
        if mode.isReturn { return !remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if case .directIssue = mode { return members.contains { $0.user_id == borrowerID } }
        return borrowerChecked
    }
    func invalidate() { active = false; generation += 1; photo = nil; evidenceID = nil; scans = [:]; members = []; products = []; returns = []; receipt = nil; error = nil; mode = .directIssue; boxCode = ""; boxLabel = ""; remark = ""; borrowerID = nil; kits = []; kitCounts = [:] }
    func loadBorrowers(more: Bool = false) async {
        guard canRequest, !more || membersNext != nil else { return }; busy = true
        let page = more ? membersNext! : 1
        do {
            let result = try await parent.repository.directMembers(page: page); guard active else { return }
            membersNext = try StaffPaging.next(result.next, after: page)
            members = StaffPaging.unique((more ? members : []) + result.results, id: { $0.user_id }); busy = false
        } catch { fail(error) }
    }
    func loadProducts(more: Bool = false) async {
        guard canRequest, !more || productsNext != nil else { return }; busy = true
        let page = more ? productsNext! : 1
        do {
            let result = try await parent.repository.inventory(page: page, search: ""); guard active else { return }
            productsNext = try StaffPaging.next(result.next, after: page)
            products = StaffPaging.unique((more ? products : []) + result.results, id: { $0.id }); busy = false
        } catch { fail(error) }
    }
    func scan(_ raw: String, box: Bool) async {
        guard canRequest, !assignmentRecorded else { return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 2048, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { error = String(localized: "Enter a valid QR payload."); return }
        busy = true; error = nil
        do {
            let result = try await parent.repository.resolveQR(body: .init(payload: value)); guard active else { return }
            guard result.qr.makerspace == parent.makerspaceID, result.qr.status.value1.rawValue == "active" else { throw validation("Scan an active code from this makerspace.") }
            let canonical = result.qr.payload
            guard !canonical.isEmpty, canonical.utf8.count <= 64,
                  !canonical.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw validation("This QR code cannot be used for a handover.") }
            let type = result.qr.target_type.rawValue
            if box {
                if let loan = mode.loan {
                    guard type == loan.target_type else { throw validation("Scan the equipment code for this loan.") }
                    if type == "box" { guard result.qr.target_id == loan.container_id else { throw validation("Scan the container for this loan.") } }
                    if type == "asset" { guard loan.return_items.flatMap(\.assets).contains(where: { $0.asset_id == result.qr.target_id }) else { throw validation("Scan an asset from this loan.") } }
                } else { guard type == "box" else { throw validation("Scan the container for this handover.") } }
                boxCode = canonical; boxLabel = result.target.additionalProperties["label"]?.value as? String ?? String(localized: "Container #\(result.qr.target_id)")
            } else {
                guard type != "box" else { throw validation("Scan an equipment or asset code here.") }
                if mode.request != nil {
                    guard type == "asset", result.target.additionalProperties["status"]?.value as? String == "available",
                          let product = StaffMetadata.positiveID(result.target.additionalProperties["product_id"]?.value),
                          mode.request?.items.contains(where: { $0.product_id == product && $0.requires_asset_qr }) == true else { throw validation("Scan an available asset from this request.") }
                } else { guard result.allowed_actions.contains("direct_handout") else { throw validation("This equipment is unavailable for direct handout.") } }
                if scans.values.contains(where: { $0.qr.id == result.qr.id }) { throw validation("This code has already been added.") }
                guard scans.count < 50 else { throw validation("A handover can contain up to 50 equipment codes.") }
                scans[canonical] = result
            }
            busy = false; kitsReady = false
        } catch { fail(error) }
    }
    func removeScan(_ value: String) { guard !busy else { return }; scans[value] = nil; kitsReady = false }
    func prepareKits() async {
        guard canRequest, itemsReady else { return }
        if !needsKits { kits = []; kitsReady = true; return }
        busy = true; error = nil; kitsReady = false
        do {
            guard let phase = Components.Schemas.PhaseEnum(rawValue: mode.isReturn ? "return" : "issue") else { throw validation("Checklist phase unavailable.") }
            let result = try await parent.repository.kitPreview(body: .init(
                phase: .init(value1: phase), request_id: mode.request?.id,
                loan_id: mode.loan?.id, box_code: boxCode.isEmpty ? nil : boxCode,
                container_id: nil, qr_payloads: Array(scans.keys).sorted(), items: mode.isDirect && !mode.isReturn ? selectedItems : nil,
                resolutions: mode.isReturn ? returns.map(\.body) : nil))
            guard active else { return }; kits = result.components
            kitCounts = [:]
            kitsReady = true; busy = false
        } catch { fail(error) }
    }
    func setPhoto(_ data: Data) {
        guard active, !busy, receipt == nil, !needsReload else { return }
        generation += 1; evidenceID = nil; error = nil
        photo = data.count <= 5 * 1024 * 1024 && data.starts(with: [0xff, 0xd8, 0xff]) ? data : nil
        if photo == nil { error = String(localized: "Choose a JPEG photo up to 5 MB.") }
    }
    func uploadPhoto() async {
        guard canRequest, let photo else { return }; busy = true; evidenceID = nil; error = nil
        let current = generation
        do {
            guard let type = Components.Schemas.EvidenceUrlRequestEvidenceTypeEnum(rawValue: mode.isReturn ? "return" : "issue") else { throw validation("Photo type unavailable.") }
            let grant = try await parent.repository.evidence(body: .init(evidence_type: type, content_type: "image/jpeg", size_bytes: photo.count))
            guard active, current == generation else { return }
            if !isDemo { try await upload(grant, photo) }
            guard active, current == generation else { return }
            evidenceID = grant.evidence_id; busy = false
        } catch { guard active, current == generation else { return }; fail(error) }
    }
    func confirm() async {
        guard ready, let evidenceID else { return }
        let permission = mode.isReturn ? "return_request" : (mode.isDirect ? "issue_direct_loan" : "issue_request")
        guard parent.can(permission), parent.can("upload_evidence"), mode.isDirect || mode.isReturn || parent.can("assign_box") else { error = String(localized: "You no longer have permission for this handover."); return }
        busy = true; error = nil
        do {
            let id: Int
            switch mode {
            case .issue(let row):
                if !assignmentRecorded {
                    _ = try await parent.repository.assignBox(id: row.id, body: .init(box_code: boxCode)); guard active else { return }
                    assignmentRecorded = true
                }
                let result = try await parent.repository.issue(id: row.id, body: .init(kit_checklist: kitBody, evidence_id: evidenceID,
                    remark: remark, asset_qr_payloads: Array(scans.keys).sorted()))
                id = result.id
            case .returnRequest(let row):
                id = try await parent.repository.returnRequest(id: row.id, body: .init(kit_checklist: kitBody, evidence_id: evidenceID,
                    box_code: boxCode, remark: remark.trimmingCharacters(in: .whitespacesAndNewlines), resolutions: returns.map(\.body))).id
            case .directIssue:
                guard let borrowerID else { throw validation("Choose a borrower.") }
                id = try await parent.repository.createDirect(body: .init(kit_checklist: kitBody, borrower_id: borrowerID,
                    evidence_id: evidenceID, remark: remark, qr_payloads: Array(scans.keys).sorted(), items: selectedItems)).id
            case .directReturn(let row):
                id = try await parent.repository.returnDirect(id: row.id, body: .init(kit_checklist: kitBody, evidence_id: evidenceID,
                    notes: remark.trimmingCharacters(in: .whitespacesAndNewlines), qr_payload: boxCode.isEmpty ? nil : boxCode, resolutions: returns.map(\.body))).id
            }
            guard active else { return }; receipt = "\(mode.isReturn ? "Return" : "Issue") #\(id) recorded"
            notice = String(localized: "Evidence photo #\(evidenceID) is attached."); busy = false; step = steps.count - 1
            await parent.loadQueue(); await parent.loadDirect()
        } catch {
            guard active else { return }; needsReload = true; fail(error)
            if assignmentRecorded { notice = String(localized: "Box assignment was recorded; issue still needs to complete. Check the latest request before retrying.") }
        }
    }
    private func validation(_ detail: String) -> APIError { APIError(status: 0, code: "handover_validation", detail: detail) }
    private func fail(_ error: Error) {
        guard active else { return }; self.error = APIError.display(error); busy = false; parent.refuse(error)
        if [401, 403].contains(APIError.status(error)) { invalidate() }
    }
}

enum StaffEvidenceUpload {
    static func send(_ grant: Components.Schemas.EvidenceUrlResponse, _ photo: Data) async throws {
        guard let url = URL(string: grant.upload_url) else { throw NativeTransferError.invalidURL }
        func strings<T: Encodable>(_ value: T) throws -> [String: String] {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            guard let fields = object as? [String: Any] else { throw NativeTransferError.invalidInput }
            var result: [String: String] = [:]
            for (key, value) in fields {
                if let text = value as? String { result[key] = text }
                else if let number = value as? NSNumber {
                    result[key] = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
                } else { throw NativeTransferError.invalidInput }
            }
            return result
        }
        let transfer = NativeFileTransfer()
        if grant.method?.uppercased() == "PUT" {
            try await transfer.uploadPUT(to: url, headers: grant.headers.map { try strings($0) } ?? [:], photo: photo, contentType: "image/jpeg", maximumBytes: 5 * 1024 * 1024)
        } else {
            guard grant.method == nil || grant.method?.uppercased() == "POST" else { throw NativeTransferError.invalidInput }
            try await transfer.uploadPOST(to: url, fields: strings(grant.fields), photo: photo, contentType: "image/jpeg", filename: "evidence.jpg", maximumBytes: 5 * 1024 * 1024)
        }
    }
}
