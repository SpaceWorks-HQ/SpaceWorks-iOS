import Foundation
import Observation
import SpaceWorksAPI

/// Member-only phone sign-in with device delivery. The attestation challenge is requested with the
/// code and must still be valid when the code is confirmed; an expired pair restarts with a new code.
@MainActor @Observable
final class PhoneSignInState: Identifiable {
    enum Step: Equatable { case number, code }
    struct Started: Sendable { let challenge: String; let expires: Date }
    let id = UUID()
    var number = ""
    var code = ""
    private(set) var step = Step.number
    private(set) var busy = false
    private(set) var error: String?
    private(set) var resendAfter = Date.distantPast
    private(set) var phone: String?
    private var started: Started?
    private let begin: @MainActor (String) async throws -> Started
    private let finish: @MainActor (String, String, String) async throws -> Void
    private let now: () -> Date

    init(begin: @escaping @MainActor (String) async throws -> Started,
         finish: @escaping @MainActor (String, String, String) async throws -> Void, now: @escaping () -> Date = Date.init) {
        self.begin = begin; self.finish = finish; self.now = now
    }

    /// E.164 with an explicit country code; spaces, dashes, dots and brackets are ignored.
    static func normalized(_ input: String) -> String? {
        let compact = input.filter { !" -().".contains($0) }
        return compact.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) == nil ? nil : compact
    }

    func send() async {
        guard !busy, now() >= resendAfter else { return }
        guard let phone = Self.normalized(step == .code ? (phone ?? number) : number) else {
            error = String(localized: "Enter your phone number with its country code."); return
        }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await begin(phone)
            self.phone = phone; started = value; code = ""; step = .code
            resendAfter = now().addingTimeInterval(60)
        } catch {
            if !APIError.isCancellation(error) { self.error = APIError.display(error) }
            if let deadline = APIError.retryDeadline(error) { resendAfter = deadline }
        }
    }

    func verify() async {
        guard !busy, let phone else { return }
        let digits = code.filter { $0.isASCII && $0.isNumber }
        guard digits.count == 6, digits.count == code.trimmingCharacters(in: .whitespaces).count else {
            error = String(localized: "Enter the six-digit code."); return
        }
        guard let started, now() < started.expires else { expire(); return }
        busy = true; error = nil
        defer { busy = false }
        do { try await finish(phone, digits, started.challenge) }
        catch {
            guard !APIError.isCancellation(error) else { return }
            if ["phone_device_restart_required", "challenge_expired"].contains(APIError.code(error) ?? "") { expire() }
            else { self.error = APIError.display(error) }
        }
    }

    func changeNumber() {
        guard !busy else { return }
        step = .number; code = ""; error = nil; started = nil
    }

    private func expire() {
        started = nil; code = ""; resendAfter = .distantPast
        error = String(localized: "Your code expired. Send a new code.")
    }
}
