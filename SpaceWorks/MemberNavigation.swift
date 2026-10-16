import SwiftUI

enum MemberRoute: Hashable {
    case product(Int), spaces, space(String), event(String), booking(String), registration(Int), contact, preferences
}

/// Memory-only navigation belongs to one authenticated account/makerspace, outside adaptive branches.
@MainActor @Observable
final class MemberNavigation {
    var selected = AppTab.home
    var inventorySelection: Int?
    private(set) var paths: [AppTab: [MemberRoute]] = [:]
    func path(_ tab: AppTab) -> Binding<[MemberRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: {
            self.paths[tab] = $0
            if tab == .inventory && $0.isEmpty { self.inventorySelection = nil }
        })
    }
    func open(_ route: MemberRoute, tab: AppTab) { selected = tab; paths[tab] = [route] }
    func compactInventory() {
        guard selected == .inventory, let inventorySelection, paths[.inventory, default: []].isEmpty else { return }
        paths[.inventory] = [.product(inventorySelection)]
    }
    func invalidate() { paths = [:]; inventorySelection = nil; selected = .home }
}
