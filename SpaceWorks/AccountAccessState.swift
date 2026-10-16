import Foundation
import Observation
import SpaceWorksAPI

@MainActor @Observable
final class AccountAccessCooldown {
    var resendAfter = Date.distantPast
    var submitAfter = Date.distantPast
    private static var scopes: [String: AccountAccessCooldown] = [:]
    static func scoped(_ key: String) -> AccountAccessCooldown {
        if let value = scopes[key] { return value }
        let value = AccountAccessCooldown(); scopes[key] = value; return value
    }
}

/// Task-local account forms. Closures make offline/demo previews independent of production transport.
@MainActor @Observable
final class AccountAccessState: Identifiable {
    let id = UUID()
    enum Step: Equatable { case signUp, created, requestReset, confirmReset, resetComplete, unavailable, emailVerification }
    var step: Step
    var name = ""
    var email = ""
    var phone = ""
    var password = ""
    var confirmation = ""
    var code = ""
    private(set) var busy = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var resendAfter: Date {
        get { cooldown.resendAfter }
        set { cooldown.resendAfter = newValue }
    }
    private(set) var submitAfter: Date {
        get { cooldown.submitAfter }
        set { cooldown.submitAfter = newValue }
    }
    private let cooldown: AccountAccessCooldown
    private let create: (String, String, String, String) async throws -> Void
    private let request: (String) async throws -> Void
    private let reset: (String, String, String) async throws -> Void
    private let verify: (String) async throws -> Void
    private let resendVerification: () async throws -> Void
    private let now: () -> Date

    init(step: Step, now: @escaping () -> Date = Date.init, cooldown: AccountAccessCooldown? = nil,
         create: @escaping (String, String, String, String) async throws -> Void,
         request: @escaping (String) async throws -> Void,
         reset: @escaping (String, String, String) async throws -> Void,
         verify: @escaping (String) async throws -> Void = { _ in },
         resendVerification: @escaping () async throws -> Void = {}) {
        self.step = step; self.now = now; self.create = create; self.request = request
        self.reset = reset; self.verify = verify; self.resendVerification = resendVerification
        self.cooldown = cooldown ?? AccountAccessCooldown()
    }
    var canResend: Bool { !busy && now() >= resendAfter }
    func signUp() async {
        guard !busy, now() >= submitAfter else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { error = "Enter your name (up to 200 characters)."; return }
        guard validEmail else { error = "Enter a valid email address."; return }
        guard validatePasswords() else { return }
        guard password.count <= 128 else { error = "Use a password with no more than 128 characters."; return }
        guard phone.count <= 32 else { error = "Use a phone number with no more than 32 characters."; return }
        await perform {
            try await self.create(trimmed, self.email.trimmingCharacters(in: .whitespacesAndNewlines), self.password, self.phone)
            self.clearSecrets(); self.step = .created
        }
    }
    func requestCode(resending: Bool = false) async {
        guard !busy, now() >= resendAfter, now() >= submitAfter else { return }
        guard validEmail else { error = "Enter a valid email address."; return }
        await perform {
            try await self.request(self.email.trimmingCharacters(in: .whitespacesAndNewlines))
            self.resendAfter = self.now().addingTimeInterval(60)
            self.notice = "If an account matches this email, a recovery code will arrive. Delivery may take a few minutes."
            self.step = .confirmReset
        }
    }
    func confirmReset() async {
        guard !busy, now() >= submitAfter else { return }
        guard isSixDigits else { error = "Enter the six-digit verification code."; return }
        guard validatePasswords() else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await reset(email.trimmingCharacters(in: .whitespacesAndNewlines), code, password)
            clearSecrets(); step = .resetComplete
        } catch {
            // Every server rejection is identical: don't expose an OTP/account-existence oracle.
            self.error = "Invalid or expired verification code."
            preserveCooldown(error)
        }
    }
    func confirmEmail() async {
        guard !busy, now() >= submitAfter else { return }
        guard isSixDigits else { error = "Enter the six-digit verification code."; return }
        await perform { try await self.verify(self.code); self.code = ""; self.notice = "Email confirmed." }
    }
    func resendEmail() async {
        guard canResend, now() >= submitAfter else { return }
        await perform {
            try await self.resendVerification()
            self.resendAfter = self.now().addingTimeInterval(60)
            self.notice = "Check your email for a verification code."
        }
    }
    func changeEmail() {
        guard !busy else { return }
        clearSecrets(); error = nil; notice = nil; step = .requestReset
        // Operation cooldown deliberately survives editing and navigation.
    }
    func clearSecrets() { password = ""; confirmation = ""; code = "" }
    private var isSixDigits: Bool { code.count == 6 && code.allSatisfy { $0.isASCII && $0.isNumber } }
    private var validEmail: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count <= 254 && value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    private func validatePasswords() -> Bool {
        guard password.count >= 8 else { error = "Use at least 8 characters."; return false }
        guard password == confirmation else { error = "Passwords don't match."; return false }
        return true
    }
    private func preserveCooldown(_ failure: Error) {
        if let deadline = APIError.retryDeadline(failure) {
            submitAfter = max(submitAfter, deadline); resendAfter = max(resendAfter, deadline)
        }
    }
    private func perform(_ operation: () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation() } catch {
            preserveCooldown(error)
            if APIError.code(error) == "recovery_unavailable" { step = .unavailable; clearSecrets() }
            else { self.error = APIError.display(error) }
        }
    }
}
