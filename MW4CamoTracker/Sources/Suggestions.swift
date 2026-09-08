import SwiftUI

/// "Grind this next" — a weapon close to Gold, or (highest priority) the one
/// weapon standing between a category and that mode's Mastery tier 1.
struct Suggestion: Identifiable {
    let id = UUID()
    let weaponId: Int
    let title: String
    let subtitle: String
    let isMasteryTier1Critical: Bool
}

/// A brief celebration shown when a weapon, category, or the whole roster
/// crosses a Gold/Mastery milestone. `titleGradient` drives the shimmering
/// title text — the real camo it's celebrating is itself an animated finish.
/// `icon` is an SF Symbol name, not an emoji — emoji read as cheap next to
/// the rest of this app's iconography.
struct MilestoneBanner: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let titleGradient: [Color]
    let icon: String
}

extension TrackerViewModel {
    /// Ranks weapons by how close they are to a milestone. A weapon that is the
    /// last one needed for a category's Mastery tier 1 always sorts first;
    /// everything else is ordered by fewest camos remaining until Gold.
    func suggestions(mode: String, limit: Int = 3) -> [Suggestion] {
        guard let categories = catalog?.categories else { return [] }
        var tier1Critical: [Suggestion] = []
        var closeToGold: [(Suggestion, Int)] = []
        let tier1Name = AppMode(rawValue: mode)?.masteryCamos.tier1.name ?? "Mastery"

        for category in categories {
            let notGold = category.weapons.filter { !allCamosComplete(weaponId: $0.weaponId, mode: mode) }

            if notGold.count == 1, let weapon = notGold.first {
                let remaining = remainingCamoCount(weaponId: weapon.weaponId, mode: mode)
                guard remaining > 0 else { continue }
                tier1Critical.append(Suggestion(
                    weaponId: weapon.weaponId,
                    title: weapon.name.resolved(),
                    subtitle: "\(remaining) camo\(remaining == 1 ? "" : "s") from \(tier1Name) in \(category.name.resolved())",
                    isMasteryTier1Critical: true
                ))
                continue
            }

            for weapon in notGold {
                let remaining = remainingCamoCount(weaponId: weapon.weaponId, mode: mode)
                guard remaining > 0 else { continue }
                closeToGold.append((Suggestion(
                    weaponId: weapon.weaponId,
                    title: weapon.name.resolved(),
                    subtitle: "\(remaining) camo\(remaining == 1 ? "" : "s") to complete",
                    isMasteryTier1Critical: false
                ), remaining))
            }
        }

        closeToGold.sort { $0.1 < $1.1 }
        let remainingSlots = max(0, limit - tier1Critical.count)
        return tier1Critical + closeToGold.prefix(remainingSlots).map(\.0)
    }

    /// Called right after a camo mutation with the weapon's Gold status from
    /// *before* the change. Just the plain Gold banner — the Mastery
    /// tier1/tier2 celebrations fire separately, from
    /// `checkWeaponMasteryMilestone`, once their own challenge is actually
    /// finished (Gold alone only *opens* tier1, it isn't earning it).
    func checkMilestone(weaponId: Int, mode: String, wasGold: Bool) {
        guard !wasGold, allCamosComplete(weaponId: weaponId, mode: mode) else { return }
        let weaponName = weapon(id: weaponId)?.name.resolved() ?? "This weapon"
        announce(title: "Camos complete", subtitle: "\(weaponName).", titleGradient: .gold, icon: "medal.fill")
    }

    /// Called right after a weapon's tier1/tier2 Mastery challenge amount
    /// changes, with whether *that weapon* had already earned *that tier*
    /// before the change, and whether the mode-wide tier3 capstone was
    /// already achieved before the change. Three things can newly become
    /// true from one nudge: this weapon's own tier, its whole category's
    /// tier1 gate (opening tier2 for every weapon in that category), and the
    /// mode-wide tier3 capstone — checked in that order so a single
    /// celebration doesn't get buried by a bigger one.
    func checkWeaponMasteryMilestone(mode: String, weaponId: Int, tier: Int, wasComplete: Bool, wasTier3Achieved: Bool, was100PlusAchieved: Bool) {
        guard !wasComplete, isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier),
              let tiers = AppMode(rawValue: mode)?.masteryCamos,
              let weaponName = weapon(id: weaponId)?.name.resolved() else { return }

        if tier == 3 { return } // tier3 has no per-weapon challenge; see below

        let camo = tier == 1 ? tiers.tier1 : tiers.tier2
        let icon = tier == 1 ? "diamond.fill" : "hexagon.fill"
        announce(title: "\(camo.name) unlocked", subtitle: weaponName, titleGradient: camo.gradient, icon: icon)

        if tier == 2, isMasteryTier3Achieved(mode: mode) {
            if wasTier3Achieved {
                // The capstone gate only needs `baseWeaponCount` weapons at
                // tier2 (see `masteryTier2Progress`), so it can already be
                // true before every weapon — including a DLC one — has
                // actually finished. This weapon just caught up to a
                // capstone the mode already has, not a fresh unlock, so it
                // gets its own name instead of repeating the original
                // "Total Mastery" celebration verbatim.
                announce(title: "\(tiers.tier3.name) unlocked", subtitle: "\(weaponName) joins Total Mastery.", titleGradient: tiers.tier3.gradient, icon: "star.fill")
            } else {
                announce(title: "\(tiers.tier3.name) unlocked", subtitle: "Every weapon, every camo. Total Mastery.", titleGradient: tiers.tier3.gradient, icon: "star.fill")
            }
        }

        // The flex milestone past tier3 itself — literally every weapon that
        // currently exists, DLC included, at tier2 (see `is100PlusAchieved`).
        // Distinct from the tier3 celebration above: tier3 only ever needs
        // `baseWeaponCount` of them, so this can land well after that one,
        // once a DLC weapon closes the gap.
        if tier == 2, !was100PlusAchieved, is100PlusAchieved(mode: mode) {
            announce(
                title: "mw4.ui.milestone.100_plus_title".localized(),
                subtitle: String(format: "mw4.ui.milestone.100_plus_subtitle".localized(), tiers.tier2.name),
                titleGradient: .platinum,
                icon: "crown.fill"
            )
        }
    }

    private func announce(title: String, subtitle: String, titleGradient: [Color], icon: String) {
        let banner = MilestoneBanner(id: UUID(), title: title, subtitle: subtitle, titleGradient: titleGradient, icon: icon)
        milestoneBanner = banner
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self?.milestoneBanner?.id == banner.id {
                self?.milestoneBanner = nil
            }
        }
    }
}
