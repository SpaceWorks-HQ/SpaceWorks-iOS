import Foundation

/// Only compile-time application copy is accepted. Remote details are never lookup keys.
enum APILocalCopy {
    static func text(_ key: StaticString) -> String {
        let source = String(describing: key)
        return NSLocalizedString(source, bundle: .module, value: source, comment: "Application fallback error")
    }
}
