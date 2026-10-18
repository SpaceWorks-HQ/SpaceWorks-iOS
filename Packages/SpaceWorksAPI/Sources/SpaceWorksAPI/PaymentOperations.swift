import Foundation
import OpenAPIRuntime

public enum PaymentOperationFailure {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        if let client = error as? ClientError { return isCancellation(client.underlyingError) }
        return false
    }
}

/// The server selects the vendor; every documented variant names the charge it prepared.
public extension Components.Schemas.MobilePaymentIntentResponse {
    var paymentID: Int {
        switch self {
        case .stripe(let value): return value.payment_id
        case .razorpay(let value): return value.payment_id
        }
    }
    /// Required SDK values are present. Format checks happen at the native SDK boundary.
    var hasCheckoutParameters: Bool {
        switch self {
        case .stripe(let value): return !value.client_secret.isEmpty && !value.publishable_key.isEmpty
        case .razorpay(let value): return !value.key_id.isEmpty && !value.order_id.isEmpty && value.amount_minor > 0 && !value.currency.isEmpty
        }
    }
}

/// A download grant authorizes a documented API operation; it is not an arbitrary browser URL.
public enum PaymentDownloadGrant {
    public static func token(from value: String, documentID: Int, origin: ServerOrigin) throws -> String {
        guard documentID > 0, value.utf8.count <= 8192, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value, relativeTo: origin.url)?.absoluteURL,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              parts.scheme == origin.url.scheme, parts.host?.lowercased() == origin.url.host?.lowercased(),
              effectivePort(url) == effectivePort(origin.url),
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == "/api/v1/payment-documents/\(documentID)/download",
              let items = parts.queryItems, items.count == 1, items[0].name == "token",
              let token = items[0].value, !token.isEmpty, token.utf8.count <= 4096,
              !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError(status: 0, code: "invalid_document_grant", detail: APILocalCopy.text("This document link is unavailable. Request a new link and try again."))
        }
        return token
    }
    private static func effectivePort(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
}

extension SpaceWorksService {
    public func memberPayments(makerspaceID: Int) async throws -> [Components.Schemas.MemberPayment] {
        try await client.api_v1_member_makerspaces_payments_list(.init(path: .init(makerspace_id: makerspaceID))).ok.body.json
    }
    public func memberPaymentIntent(makerspaceID: Int, paymentID: Int) async throws -> Components.Schemas.MobilePaymentIntentResponse {
        try await client.api_v1_member_makerspaces_payments_mobile_intent_create(
            .init(path: .init(makerspace_id: makerspaceID, payment_id: paymentID))).ok.body.json
    }
    public func memberPaymentDocuments(makerspaceID: Int, page: Int) async throws -> Components.Schemas.DocumentPage {
        try await client.api_v1_member_makerspaces_payment_documents_retrieve(
            .init(path: .init(makerspace_id: makerspaceID), query: .init(page: page))).ok.body.json
    }
    public func memberPaymentPDF(makerspaceID: Int, documentID: Int, origin: ServerOrigin) async throws -> Data {
        let grant = try await client.api_v1_member_makerspaces_payment_documents_download_url_retrieve(
            .init(path: .init(document_id: documentID, makerspace_id: makerspaceID))).ok.body.json
        guard grant.expires_in > 0 else {
            throw APIError(status: 0, code: "expired_document_grant", detail: APILocalCopy.text("This document link expired. Try again to request a new link."))
        }
        let token = try PaymentDownloadGrant.token(from: grant.url, documentID: documentID, origin: origin)
        // This operation requires the authenticated generated client even with the signed token.
        let body = try await client.api_v1_payment_documents_download_retrieve(
            .init(path: .init(document_id: documentID), query: .init(token: token))).ok.body.pdf
        return try await Data(collecting: body, upTo: 25 * 1024 * 1024)
    }
}
