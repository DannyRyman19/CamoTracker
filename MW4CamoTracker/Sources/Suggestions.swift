import Foundation

/// "Grind this next" — a weapon close to Gold, or (highest priority) the one
/// weapon standing between a category and Diamond.
struct Suggestion: Identifiable {
    let id = UUID()
    let weaponId: Int
    let title: String
    let subtitle: String
    let isDiamondCritical: Bool
}

/// A brief celebration shown when a weapon or category crosses Gold/Diamond.
struct MilestoneBanner: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
}

extension TrackerViewModel {
    /// Ranks weapons by how close they are to a milestone. A weapon that is the
    /// last one needed for a category's Diamond always sorts first; everything
    /// else is ordered by fewest camos remaining until Gold.
    func suggestions(mode: String, limit: Int = 3) -> [Suggestion] {
        guard let categories = catalog?.categories else { return [] }
        var diamondCritical: [Suggestion] = []
        var closeToGold: [(Suggestion, Int)] = []

        for category in categories {
            let notGold = category.weapons.filter { !allCamosComplete(weaponId: $0.weaponId, mode: mode) }

            if notGold.count == 1, let weapon = notGold.first {
                let remaining = remainingCamoCount(weaponId: weapon.weaponId, mode: mode)
                guard remaining > 0 else { continue }
                diamondCritical.append(Suggestion(
                    weaponId: weapon.weaponId,
                    title: weapon.name.resolved(),
                    subtitle: "\(remaining) camo\(remaining == 1 ? "" : "s") from Diamond in \(category.name.resolved())",
                    isDiamondCritical: true
                ))
                continue
            }

            for weapon in notGold {
                let remaining = remainingCamoCount(weaponId: weapon.weaponId, mode: mode)
                guard remaining > 0 else { continue }
                closeToGold.append((Suggestion(
                    weaponId: weapon.weaponId,
                    title: weapon.name.resolved(),
                    subtitle: "\(remaining) camo\(remaining == 1 ? "" : "s") from Gold",
                    isDiamondCritical: false
                ), remaining))
            }
        }

        closeToGold.sort { $0.1 < $1.1 }
        let remainingSlots = max(0, limit - diamondCritical.count)
        return diamondCritical + closeToGold.prefix(remainingSlots).map(\.0)
    }

    /// Called right after a camo mutation with the weapon's Gold status from
    /// *before* the change. If it just flipped to Gold, checks whether that
    /// was also the last weapon a category needed for Diamond — this is the
    /// "you just finished the 5th SMG" moment.
    func checkMilestone(weaponId: Int, mode: String, wasGold: Bool) {
        guard !wasGold, allCamosComplete(weaponId: weaponId, mode: mode) else { return }

        let weaponName = weapon(id: weaponId)?.name.resolved() ?? "This weapon"
        if let category = category(containingWeaponId: weaponId), categoryIsDiamond(category, mode: mode) {
            announce(
                title: "💎 Diamond unlocked",
                subtitle: "\(category.name.resolved()) — every weapon just went Gold."
            )
        } else {
            announce(title: "🥇 Gold unlocked", subtitle: "\(weaponName) is fully camo'd.")
        }
    }

    private func announce(title: String, subtitle: String) {
        let banner = MilestoneBanner(id: UUID(), title: title, subtitle: subtitle)
        milestoneBanner = banner
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self?.milestoneBanner?.id == banner.id {
                self?.milestoneBanner = nil
            }
        }
    }
}
