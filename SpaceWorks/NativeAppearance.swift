import UIKit

/// Keep modern system navigation materials; older bars use adaptive semantic assets.
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
        // UIKit supplies Liquid Glass and scroll-edge treatment on iOS 26.
        // Custom appearance backgrounds can cover those system materials (Apple TN3106).
        if #available(iOS 26, *) {
            navigation.tintColor = color("accent-ink")
            UITabBar.appearance().tintColor = color("accent-ink")
            return
        }
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
