import SwiftUI

/// Value-based destinations for each mode's `NavigationStack`. Using values
/// instead of nested `NavigationLink(destination:)` lets a Suggested-row tap
/// jump straight to a weapon's detail screen without passing through its
/// category list first.
enum Route: Hashable {
    case weaponCategory(Int)
    case weapon(Int)
    case objectiveCategory(Int)
    /// One objective item (a live event or BlackCell season), straight to its challenges.
    case objectiveItem(categoryId: Int, itemId: Int)
    /// Every weapon in one list, across classes.
    case allWeapons
}

/// The app's links (`mw4camo://mode/<mode>/...`), from the widgets and from
/// notifications:
///
///     mw4camo://mode/warzone                       the Weapons tab in Warzone
///     mw4camo://mode/warzone/weapon/12             a weapon's page
///     mw4camo://mode/warzone/event/1/102           an event (objective category 1, item 102)
///     mw4camo://mode/current/event/1/102           the same, in whichever mode the player is on
///
/// `?game=bo7` switches game first. A mode the player doesn't play (or
/// `current`) opens in their own.
enum DeepLink {
    struct Target: Equatable {
        /// nil: the player's current mode
        let mode: String?
        let route: Route?
        let game: String?
    }

    /// A notification's link waiting for the screens (a tap can launch the app
    /// before they exist); ContentView takes it when it appears, or at once.
    @MainActor static var pending: URL?
    static let arrived = Notification.Name("ct.deepLink.arrived")

    @MainActor static func open(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: arrived, object: nil)
    }

    static func parse(_ url: URL) -> Target? {
        guard url.scheme == "mw4camo", url.host == "mode" else { return nil }
        let game = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "game" }?.value
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return nil }
        let mode = first == "current" ? nil : first
        var route: Route?
        if parts.count >= 3, parts[1] == "weapon", let id = Int(parts[2]) {
            route = .weapon(id)
        } else if parts.count >= 4, parts[1] == "event", let category = Int(parts[2]), let item = Int(parts[3]) {
            route = .objectiveItem(categoryId: category, itemId: item)
        } else if parts.count >= 3, parts[1] == "events", let category = Int(parts[2]) {
            route = .objectiveCategory(category)
        }
        return Target(mode: mode, route: route, game: game)
    }
}

struct RouteDestinationView: View {
    let mode: AppMode
    let route: Route
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        switch route {
        case .weaponCategory(let categoryId):
            if let category = viewModel.categories(mode: mode.rawValue).first(where: { $0.categoryId == categoryId })
                ?? viewModel.catalog?.categories.first(where: { $0.categoryId == categoryId }) {
                WeaponListView(mode: mode, category: category)
            }
        case .weapon(let weaponId):
            if let weapon = viewModel.weapon(id: weaponId) {
                WeaponDetailView(mode: mode, weapon: weapon)
            }
        case .allWeapons:
            if let all = viewModel.allWeaponsCategory(mode: mode.rawValue) {
                WeaponListView(mode: mode, category: all)
            }
        case .objectiveCategory(let categoryId):
            if let category = viewModel.modes[mode.rawValue]?.objectives.first(where: { $0.categoryId == categoryId }) {
                ItemListView(mode: mode, category: category)
            }
        case .objectiveItem(let categoryId, let itemId):
            if let category = viewModel.modes[mode.rawValue]?.objectives.first(where: { $0.categoryId == categoryId }),
               let item = category.items.first(where: { $0.itemId == itemId }) {
                ItemDetailView(mode: mode, category: category, item: item)
            }
        }
    }
}
