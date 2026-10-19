import Foundation

/// Formats a retained deadline without converting an unbounded server interval to Int.
/// The display never changes the deadline or authorizes a request.
enum CooldownCopy {
    private static func seconds(until deadline: Date, now: Date) -> Int? {
        let remaining = deadline.timeIntervalSince(now)
        guard remaining.isFinite else { return nil }
        return Int(exactly: max(1, remaining.rounded(.up)))
    }
    static func retryMessage(until deadline: Date, now: Date) -> String {
        guard let value = seconds(until: deadline, now: now) else { return String(localized: "Try again later.") }
        return String(localized: "Try again in \(value)s.")
    }
    static func retryButton(until deadline: Date, now: Date) -> String {
        guard let value = seconds(until: deadline, now: now) else { return String(localized: "Try again later") }
        return String(localized: "Try again in \(value)s")
    }
    static func resendButton(until deadline: Date, now: Date) -> String {
        guard let value = seconds(until: deadline, now: now) else { return String(localized: "Send another code later") }
        return String(localized: "Send another code in \(value)s")
    }
}
