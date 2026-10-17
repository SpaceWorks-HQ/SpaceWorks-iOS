#if DEBUG
import Foundation
import SpaceWorksAPI
import SwiftUI

enum DemoAccountScenario: String, CaseIterable, Sendable {
    case populated = "Populated", requiredMFA = "Required MFA", noMFA = "No authenticator"
    case blockedMembership = "Outstanding loan", offline = "Error", throttled = "Too many requests"
}
enum DemoAccountLinkOutcome: String, CaseIterable, Sendable { case success = "Success", cancelled = "Cancelled", unavailable = "Unavailable", conflict = "Already linked elsewhere" }
protocol DemoAccountLinking: AccountRepository {
    func linkProvider(_ provider: String, outcome: DemoAccountLinkOutcome) async throws -> Components.Schemas.SocialIdentity
}

actor DemoAccountRepository: DemoAccountLinking {
    nonisolated let isDemo = true
    let scenario: DemoAccountScenario
    private var revokedSessions = Set<String>()
    private var revokedGrants = Set<String>()
    private var providerNames = ["google"]
    private var exportStatus = "available"
    private var renewalCancelled = false
    private var left = false
    private var phonePending: String?
    private var linkedPhone = ""
    private var enabled = true
    init(scenario: DemoAccountScenario = .populated) { self.scenario = scenario; enabled = scenario != .noMFA }
    private func checked() throws {
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        if scenario == .throttled { throw APIError(status: 429, code: "throttled", detail: String(localized: "Too many requests. Try again later."), retryAfter: Date().addingTimeInterval(60)) }
    }
    private func decode<T: Decodable>(_ json: String, changes: [String: Any] = [:]) throws -> T {
        try checked(); var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        object.merge(changes) { _, new in new }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func grants() throws -> [Components.Schemas.DeviceGrant] {
        let rows = try JSONSerialization.jsonObject(with: Data(DebugAccountFixtures.grants.utf8)) as! [[String: Any]]
        return try rows.filter { !revokedGrants.contains($0["id"] as! String) }.map { try decode(String(decoding: JSONSerialization.data(withJSONObject: $0), as: UTF8.self)) }
    }
    func revokeGrant(id: String) throws { try checked(); revokedGrants.insert(id); revokedSessions.insert("device:" + id) }
    func sessions(page: Int) throws -> Components.Schemas.AccountSessionPage {
        let value: Components.Schemas.AccountSessionPage = try decode(DebugAccountFixtures.sessions)
        let rows = page == 1 ? value.results.filter { !revokedSessions.contains($0.id) } : []
        return .init(count: rows.count, next: nil, previous: nil, results: rows)
    }
    func revokeSession(id: String) throws { try checked(); revokedSessions.insert(id) }
    func membership() throws -> Components.Schemas.MembershipAccount {
        try decode(DebugAccountFixtures.membership, changes: ["status": left ? "revoked" : "active", "renewal_cancelled_at": renewalCancelled ? ISO8601DateFormatter().string(from: Date()) : NSNull()])
    }
    func leave(reason: String) throws -> Components.Schemas.MembershipAccount {
        try checked(); if scenario == .blockedMembership { throw APIError(status: 423, code: "outstanding_loans", detail: String(localized: "Return outstanding equipment before leaving this makerspace.")) }
        left = true; return try membership()
    }
    func cancelRenewal(reason: String) throws -> Components.Schemas.MembershipAccount { try checked(); renewalCancelled = true; return try membership() }
    func exports(page: Int) throws -> Components.Schemas.SubjectExportList {
        let row = try export(id: "84000000-0000-4000-8000-000000000001")
        return .init(count: 1, next: nil, previous: nil, results: page == 1 ? [row] : [])
    }
    func requestExport() throws -> Components.Schemas.SubjectExport { try checked(); exportStatus = "pending"; return try exportRow() }
    func export(id: String) throws -> Components.Schemas.SubjectExport { try checked(); exportStatus = "available"; return try exportRow() }
    private func exportRow() throws -> Components.Schemas.SubjectExport {
        try decode(DebugAccountFixtures.export, changes: ["status": exportStatus, "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(7 * 86400))])
    }
    func exportDownload(id: String) throws -> Components.Schemas.DataExportDownloadUrl {
        try checked(); return .init(url: "https://demo.example.invalid/api/v1/data-exports/download/\(id)/demo-token", expires_at: Date().addingTimeInterval(300))
    }
    func exportArchive(id: String) throws -> Data {
        try checked(); let object = try JSONSerialization.jsonObject(with: Data(DebugAccountFixtures.archive.utf8)) as! [String: String]
        guard let data = Data(base64Encoded: object["base64"] ?? "") else { throw NativeTransferError.unsupportedDocument }; return data
    }
    func mfa() throws -> Components.Schemas.MFAStatus { try decode(DebugAccountFixtures.mfa, changes: ["required": scenario == .requiredMFA, "enabled": enabled]) }
    func startMFA(password: String) throws -> Components.Schemas.MFAChallengeResponse { try validPassword(password); return try decode(DebugAccountFixtures.challenge) }
    func disableMFA(password: String) throws -> Components.Schemas.MFAStatus {
        try validPassword(password); guard scenario != .requiredMFA else { throw APIError(status: 403, code: "mfa_required", detail: String(localized: "This account requires two-step sign-in.")) }
        enabled = false; return try mfa()
    }
    func regenerateRecovery(password: String) throws -> Components.Schemas.MFARecovery { try validPassword(password); return try decode(DebugAccountFixtures.recovery) }
    private func validPassword(_ value: String) throws {
        try checked(); if value != "DemoPass!123" { throw APIError(status: 0, code: "password_verification_failed", detail: String(localized: "Password verification failed.")) }
    }
    func startPhone(phone: String) throws -> Components.Schemas.PhoneStartResponse { try checked(); phonePending = phone; return .init(detail: "Demo code sent. No message was sent.") }
    func confirmPhone(phone: String, code: String) throws -> Components.Schemas.PhoneStatus {
        try checked(); guard phonePending == phone, code == "123456" else { throw APIError(status: 400, code: "invalid_code", detail: String(localized: "Invalid or expired verification code.")) }
        linkedPhone = phone; phonePending = nil; return .init(phone_e164: phone, verified: true)
    }
    func unlinkPhone() throws -> Components.Schemas.PhoneStatus { try checked(); linkedPhone = ""; phonePending = nil; return .init(phone_e164: "", verified: false) }
    func providers() throws -> [Components.Schemas.SocialIdentity] { try providerNames.map { try decode(DebugAccountFixtures.provider, changes: ["provider": $0]) } }
    func unlinkProvider(_ provider: String) throws {
        try checked(); guard providerNames.count > 1 else { throw APIError(status: 409, code: "last_sign_in_method", detail: String(localized: "Add another sign-in method before removing this one.")) }; providerNames.removeAll { $0 == provider }
    }
    func linkProvider(_ provider: String, outcome: DemoAccountLinkOutcome) throws -> Components.Schemas.SocialIdentity {
        try checked()
        switch outcome {
        case .cancelled: throw CancellationError()
        case .unavailable: throw APIError(status: 503, code: "provider_unavailable", detail: String(localized: "This provider is unavailable. Try again later."))
        case .conflict: throw APIError(status: 409, code: "provider_already_linked", detail: String(localized: "This sign-in method is already connected to another account."))
        case .success: if !providerNames.contains(provider) { providerNames.append(provider) }; return try decode(DebugAccountFixtures.provider, changes: ["provider": provider])
        }
    }
    func changePassword(current: String, new: String) throws { try validPassword(current) }
    func validateSession() throws {
        try checked(); if revokedGrants.contains("83000000-0000-4000-8000-000000000001") { throw APIError(status: 401, code: "device_revoked", detail: String(localized: "This device was signed out.")) }
    }
}

struct DemoAccountProviderLinks: View {
    let state: AccountState
    @State private var provider: String?
    @State private var outcome = DemoAccountLinkOutcome.success
    var body: some View {
        SWCard {
            Text("Preview provider linking").brandFont(.headline)
            Text("Demo mode. No provider account is connected.").foregroundStyle(Color.swMuted)
            Picker("Preview result", selection: $outcome) { ForEach(DemoAccountLinkOutcome.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) } }.frame(minHeight: 48)
            if !state.providers.contains(where: { $0.provider == "google" }) { GoogleProviderButton(wide: false) { provider = "google" } }
            if !state.providers.contains(where: { $0.provider == "apple" }) { AppleProviderButton { provider = "apple" }.frame(height: 48) }
        }.confirmationDialog("Connect a sample provider?", isPresented: Binding(get: { provider != nil }, set: { if !$0 { provider = nil } }), titleVisibility: .visible) {
            if let provider { Button("Continue demo account") { self.provider = nil; Task { await state.previewProviderLink(provider, outcome: outcome) } } }
            Button("Cancel", role: .cancel) { provider = nil }
        }
    }
}
#endif
