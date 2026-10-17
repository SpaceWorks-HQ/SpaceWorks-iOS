import Foundation

/// Local labels for known contract values. Unknown server values stay verbatim.
enum NativeStatusCopy {
    static func label(_ raw: String) -> String {
        switch raw {
        case "active": return String(localized: "Active")
        case "pending": return String(localized: "Pending")
        case "closed": return String(localized: "Closed")
        case "cancelled": return String(localized: "Cancelled")
        case "approved": return String(localized: "Approved")
        case "rejected": return String(localized: "Rejected")
        case "returned": return String(localized: "Returned")
        case "issued": return String(localized: "Issued")
        case "accepted": return String(localized: "Accepted")
        case "overdue": return String(localized: "Overdue")
        case "registered": return String(localized: "Registered")
        case "waitlisted": return String(localized: "Waitlisted")
        case "pending_approval": return String(localized: "Pending approval")
        case "pending_payment": return String(localized: "Pending payment")
        case "paid": return String(localized: "Paid")
        case "paid_online": return String(localized: "Paid online")
        case "paid_offline": return String(localized: "Paid at the desk")
        case "payment_pending": return String(localized: "Payment pending")
        case "failed": return String(localized: "Failed")
        case "processing": return String(localized: "Processing")
        case "refunded": return String(localized: "Refunded")
        case "partially_refunded": return String(localized: "Partially refunded")
        case "unpaid": return String(localized: "Unpaid")
        case "running": return String(localized: "Running")
        case "available": return String(localized: "Available")
        case "expired": return String(localized: "Expired")
        case "revoked": return String(localized: "Revoked")
        case "not_issued": return String(localized: "Not issued")
        case "pending_review": return String(localized: "Pending review")
        case "google": return String(localized: "Google")
        case "apple": return String(localized: "Apple")
        case "android": return String(localized: "Android")
        case "ios": return String(localized: "iOS")
        case "web": return String(localized: "Web")
        case "hardware_requests": return String(localized: "Hardware requests")
        case "events": return String(localized: "Events")
        case "bookings": return String(localized: "Bookings")
        case "membership": return String(localized: "Membership")
        case "notifications": return String(localized: "Notifications")
        case "loan_overdue": return String(localized: "Overdue loans")
        case "Available": return String(localized: "Available")
        case "Limited": return String(localized: "Limited")
        case "Full": return String(localized: "Full")
        default: return raw
        }
    }
}
