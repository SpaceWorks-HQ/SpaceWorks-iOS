import Foundation
import SpaceWorksAPI

/// Local navigation vocabulary, not an API route or authority claim.
struct MobileLink: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        case home, inventory, product(Int), activity, inbox, profile, bookings, booking(String), events, event(String), registrations(Int), spaces, space(String), payments, payment(Int)
    }
    let makerspaceID: Int
    let destination: Destination
    static func notification(_ hint: NotificationHint) -> MobileLink {
        guard hint.version == 2, let relative = hint.relativeLink, let link = path(relative), link.makerspaceID == hint.makerspaceID else { return .init(makerspaceID: hint.makerspaceID, destination: .inbox) }
        return link
    }
    /// A shared-host web path (`/m/{slug}/…`) from the server's mobile link contract. The slug is resolved
    /// against a fresh membership list before any navigation.
    struct Legacy: Equatable {
        let slug: String
        let staffInbox: Bool
        let expectedMakerspaceID: Int?
        let destination: Destination
        init(slug: String, staffInbox: Bool, expectedMakerspaceID: Int? = nil, destination: Destination = .home) {
            self.slug = slug; self.staffInbox = staffInbox; self.expectedMakerspaceID = expectedMakerspaceID; self.destination = destination
        }
        /// The membership-scoped intent once the slug has resolved to an authorized makerspace.
        func link(makerspaceID: Int) -> MobileLink { MobileLink(makerspaceID: makerspaceID, destination: staffInbox ? .inbox : destination) }
    }
    static func legacy(_ raw: String, origin: ServerOrigin? = nil) -> Legacy? {
        let path: String
        if raw.hasPrefix("/") { path = raw }
        else {
            guard let origin, let url = URL(string: raw), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme == origin.url.scheme, parts.host?.lowercased() == origin.url.host?.lowercased(),
                  (parts.port ?? (parts.scheme == "https" ? 443 : 80)) == (origin.url.port ?? (origin.url.scheme == "https" ? 443 : 80)), parts.user == nil, parts.password == nil,
                  parts.query == nil, parts.fragment == nil else { return nil }
            path = parts.percentEncodedPath
        }
        guard !path.contains("%"), !path.contains("\\"), !path.contains("//"), !path.contains("?"), !path.contains("#"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let pieces = path.split(separator: "/").map(String.init)
        guard pieces.count >= 3, pieces[0] == "m", pieces[1].count <= 200,
              pieces[1].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        if pieces.count == 4, pieces[2] == "admin", pieces[3] == "notifications" { return Legacy(slug: pieces[1], staffInbox: true) }
        guard let destination = contract(Array(pieces.dropFirst(2))) else { return nil }
        return Legacy(slug: pieces[1], staffInbox: false, destination: destination)
    }
    /// The custom-domain form of the contract: the verified host names the makerspace, so the path has no
    /// `/m/{slug}` prefix. Only usable where the makerspace is already known (a push payload or its inbox).
    static func customDomain(_ path: String) -> Destination? {
        guard path.utf8.count <= 2048, path.hasPrefix("/"), !path.contains("//"), !path.contains("%"), !path.contains("\\"),
              !path.contains("?"), !path.contains("#"), path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return contract(path.split(separator: "/").map(String.init))
    }
    /// DESTINATIONS from the backend's mobile_link_contract.py, after any `/m/{slug}` prefix.
    /// Staff admin, control, API and other web pages are never claimed.
    private static func contract(_ pieces: [String]) -> Destination? {
        guard !pieces.contains("."), !pieces.contains("..") else { return nil }
        switch pieces.count {
        case 1 where pieces[0] == "member": return .home
        case 2 where pieces[0] == "member":
            switch pieces[1] {
            case "account": return .profile
            case "loans": return .activity
            case "bookings": return .bookings
            case "events": return .events
            case "payments": return .payments
            case "inbox": return .inbox
            default: return .home
            }
        case 2 where pieces[0] == "events": return uuid(pieces[1]).map { .event($0) }
        case 2 where pieces[0] == "bookings": return uuid(pieces[1]).map { .booking($0) }
        case 2 where pieces[0] == "items": return positive(pieces[1]).map { .product($0) }
        case 4 where pieces[0] == "member" && pieces[1] == "events" && pieces[3] == "ticket": return positive(pieces[2]).map { .registrations($0) }
        default: return nil
        }
    }
    static func inbox(_ value: String, origin: ServerOrigin) -> MobileLink? {
        if value.hasPrefix("/") { return path(value) }
        guard let value = URL(string: value) else { return nil }
        return url(value, origin: origin)
    }
    static func url(_ url: URL, origin: ServerOrigin) -> MobileLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, !parts.percentEncodedPath.contains("%") else { return nil }
        if parts.scheme?.lowercased() == "spaceworks" {
            if parts.host == nil || parts.host == "" { return path(parts.path) }
            guard parts.host?.lowercased() == "makerspaces", parts.port == nil else { return nil }
            return path("/makerspaces" + parts.path)
        }
        let selected = origin.url
        let scheme = parts.scheme?.lowercased()
        guard scheme == selected.scheme?.lowercased(), parts.host?.lowercased() == selected.host?.lowercased(),
              (parts.port ?? (scheme == "https" ? 443 : 80)) == (selected.port ?? (selected.scheme == "https" ? 443 : 80)) else { return nil }
        return path(parts.path)
    }
    static func path(_ path: String) -> MobileLink? {
        guard path.utf8.count <= 2048, path.hasPrefix("/"), !path.contains("//"), !path.contains("%"), !path.contains("\\"),
              !path.contains("?"), !path.contains("#"), path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let pieces = path.split(separator: "/").map(String.init)
        guard pieces.count >= 3, pieces[0] == "makerspaces", let makerspace = positive(pieces[1]), !pieces.contains("."), !pieces.contains("..") else { return nil }
        var destination: Destination = .inbox
        if pieces.count == 3 {
            switch pieces[2] {
            case "home": destination = .home
            case "inventory": destination = .inventory
            case "activity": destination = .activity
            case "inbox": destination = .inbox
            case "profile": destination = .profile
            case "bookings": destination = .bookings
            case "events": destination = .events
            case "spaces": destination = .spaces
            case "payments": destination = .payments
            default: break
            }
        } else if pieces.count == 4 {
            switch pieces[2] {
            case "inventory": if let id = positive(pieces[3]) { destination = .product(id) }
            case "registrations": if let id = positive(pieces[3]) { destination = .registrations(id) }
            case "payments": if let id = positive(pieces[3]) { destination = .payment(id) }
            case "bookings": if let token = uuid(pieces[3]) { destination = .booking(token) }
            case "events": if let token = uuid(pieces[3]) { destination = .event(token) }
            case "spaces": if let token = uuid(pieces[3]) { destination = .space(token) }
            default: break
            }
        }
        return .init(makerspaceID: makerspace, destination: destination)
    }
    private static func positive(_ value: String) -> Int? {
        guard !value.isEmpty, value.count <= 19, value.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(value), id > 0 else { return nil }; return id
    }
    private static func uuid(_ value: String) -> String? {
        guard value.count == 36, let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value.lowercased() else { return nil }; return uuid.uuidString.lowercased()
    }
}
