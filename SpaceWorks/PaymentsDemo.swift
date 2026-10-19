#if DEBUG
import Foundation
import SpaceWorksAPI
import UIKit

enum DemoPaymentScenario: Equatable {
    case paid, pending, failed, cancelled
    var outcome: NativePaymentOutcome {
        switch self {
        case .paid, .pending: return .awaitingServerConfirmation
        case .failed: return .failed("Demo checkout failed. No money moved.")
        case .cancelled: return .cancelled
        }
    }
}
protocol DemoPaymentControlling: PaymentRepository {
    func simulate(paymentID: Int, scenario: DemoPaymentScenario) async
}

/// Isolated sample records. This type and its fixtures do not exist in Release builds.
actor DemoPaymentRepository: DemoPaymentControlling {
    private var confirmed = false
    func payments() async throws -> [Components.Schemas.MemberPayment] {
        let first = try fixture(id: 501, label: "Sample equipment deposit", amount: "250.00", status: confirmed ? "paid_online" : "pending")
        let second = try fixture(id: 502, label: "Sample workshop booking", amount: "150.00", status: "paid_offline")
        return [first, second]
    }
    func intent(paymentID: Int) async throws -> Components.Schemas.MobilePaymentIntentResponse {
        throw APIError(status: 0, code: "demo_no_sdk", detail: String(localized: "Demo mode never opens a payment provider."))
    }
    func simulate(paymentID: Int, scenario: DemoPaymentScenario) async {
        guard paymentID == 501 else { return }
        confirmed = scenario == .paid
    }
    func documents(page: Int) async throws -> Components.Schemas.DocumentPage {
        let receipt = #"{"id":902,"payment":502,"number":"DEMO-RECEIPT-002","kind":"receipt","issued_at":"2026-10-16T09:00:00Z","money_at":"2026-10-16T09:00:00Z","amount":"150.00","currency":"inr"}"#
        let newReceipt = #"{"id":901,"payment":501,"number":"DEMO-RECEIPT-001","kind":"receipt","issued_at":"2026-10-16T09:00:00Z","money_at":"2026-10-16T09:00:00Z","amount":"250.00","currency":"inr"}"#
        let results = page == 1 ? (confirmed ? "\(newReceipt),\(receipt)" : receipt) : ""
        return try decode("{\"count\":\(confirmed ? 2 : 1),\"next\":null,\"previous\":null,\"results\":[\(results)]}")
    }
    func documentPDF(documentID: Int) async throws -> Data {
        guard documentID == 902 || (confirmed && documentID == 901) else {
            throw APIError(status: 404, code: "not_found", detail: String(localized: "Demo document unavailable."))
        }
        return await MainActor.run {
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
            return renderer.pdfData { context in
                context.beginPage()
                let text = "SPACE WORKS\n\nDEMO RECEIPT · SAMPLE DATA\n\nNo money moved.\nThis document previews the receipt flow."
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18)]
                text.draw(in: CGRect(x: 48, y: 64, width: 499, height: 500), withAttributes: attributes)
            }
        }
    }
    private func fixture(id: Int, label: String, amount: String, status: String) throws -> Components.Schemas.MemberPayment {
        try decode("""
        {"id":\(id),"subject_type":"booking","subject_label":"\(label)","status":"\(status)","amount":"\(amount)",
        "currency":"inr","due_at":null,"due_date":"2026-10-20","due_state":"upcoming","checkout_url":"",
        "online_payment_available":true,"settlement":null,"refunded_amount":0,"refunds":[],"created_at":"2026-10-16T09:00:00Z"}
        """)
    }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
#endif
