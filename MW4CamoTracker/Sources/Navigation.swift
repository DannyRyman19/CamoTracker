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

struct RouteDestinationView: View {
    let mode: AppMode
    let route: Route
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        switch route {
        case .weaponCategory(let categoryId):
            if let category = viewModel.catalog?.categories.first(where: { $0.categoryId == categoryId }) {
                WeaponListView(mode: mode, category: category)
            }
        case .weapon(let weaponId):
            if let weapon = viewModel.weapon(id: weaponId) {
                WeaponDetailView(mode: mode, weapon: weapon)
            }
        case .allWeapons:
            if let all = viewModel.allWeaponsCategory {
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
