import Foundation

/// The server's `native.min_app_version.ios` gate compares dotted numeric components, never strings.
enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// A missing or malformed minimum never blocks; a version that cannot be read is treated as outdated.
    static func isBelow(_ version: String, minimum: String?) -> Bool {
        guard let minimum, let required = components(minimum) else { return false }
        guard let actual = components(version) else { return true }
        for index in 0..<max(required.count, actual.count) {
            let have = index < actual.count ? actual[index] : 0
            let need = index < required.count ? required[index] : 0
            if have != need { return have < need }
        }
        return false
    }

    static func components(_ value: String) -> [Int]? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 6 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }
}
