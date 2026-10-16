import UIKit

/// Native bars use the same adaptive semantic assets as SwiftUI content.
@MainActor
enum NativeAppearance {
    static func color(_ role: String) -> UIColor {
        guard let color = UIColor(named: role) else {
            preconditionFailure("Missing generated semantic color: \(role)")
        }
        return color
    }

    static func navigation() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = color("surface")
        appearance.titleTextAttributes = [.foregroundColor: color("ink")]
        appearance.largeTitleTextAttributes = [.foregroundColor: color("ink")]
        appearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: color("accent-ink")]
        appearance.doneButtonAppearance.normal.titleTextAttributes = [.foregroundColor: color("accent-ink")]
        return appearance
    }

    static func tabs() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = color("surface")
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = color("muted")
            layout.normal.titleTextAttributes = [.foregroundColor: color("muted")]
            layout.selected.iconColor = color("accent-ink")
            layout.selected.titleTextAttributes = [.foregroundColor: color("accent-ink")]
            for state in [layout.normal, layout.selected] {
                state.badgeBackgroundColor = color("danger")
                state.badgeTextAttributes = [.foregroundColor: color("bg")]
            }
        }
        return appearance
    }

    static func apply() {
        let navigation = UINavigationBar.appearance()
        let navigationStyle = self.navigation()
        navigation.standardAppearance = navigationStyle
        navigation.scrollEdgeAppearance = navigationStyle
        navigation.compactAppearance = navigationStyle
        navigation.compactScrollEdgeAppearance = navigationStyle
        navigation.tintColor = color("accent-ink")

        let tabs = UITabBar.appearance()
        let tabStyle = self.tabs()
        tabs.standardAppearance = tabStyle
        tabs.scrollEdgeAppearance = tabStyle
        tabs.tintColor = color("accent-ink")
        tabs.unselectedItemTintColor = color("muted")
    }
}
