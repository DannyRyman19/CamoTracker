import SwiftUI

/// "Grind this next": a weapon close to finishing its camo list, or one
/// working through its Completionist camos (highlighted in that camo's color).
struct Suggestion: Identifiable {
    let id = UUID()
    let weaponId: Int
    let title: String
    let subtitle: String
    /// The Completionist camo this weapon is on, for its badge; nil for a
    /// weapon still on its camo list.
    let highlight: Color?
    /// That camo's gradient, where it has one (Gold to Mastery), drawn in
    /// place of the flat color.
    var gradient: [Color]? = nil
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
    /// The weapon it's for, whose picture goes on the share card.
    var weaponId: Int? = nil
}

extension TrackerViewModel {
    /// How long a milestone banner stays up.
    static let bannerNanoseconds: UInt64 = 6_000_000_000

    /// Ranks weapons by how close they are to their next camo. Weapons
    /// already into their Completionist camos come first, furthest along
    /// first; then weapons by fewest camos left on their list.
    func suggestions(mode: String, limit: Int = 3) -> [Suggestion] {
        guard let categories = catalog?.categories, let appMode = AppMode(rawValue: mode) else { return [] }
        let steps = appMode.completionist.steps
        var onCompletionist: [(Suggestion, Int)] = []
        var onCamoList: [(Suggestion, Int)] = []

        for category in categories {
            for weapon in category.weapons {
                let weaponId = weapon.weaponId
                if allCamosComplete(weaponId: weaponId, mode: mode) {
                    // The next Completionist camo still to earn, if any.
                    guard let next = (0..<Self.completionistStepCount).first(where: {
                        !isCompletionistComplete(mode: mode, weaponId: weaponId, step: $0)
                    }) else {
                        // Past Harmonic Break: an open Mastery challenge, if any.
                        let tiers = appMode.masteryCamos
                        if let tier = (1...3).first(where: {
                            !isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: $0)
                                && isWeaponMasteryAvailable(mode: mode, weaponId: weaponId, tier: $0)
                        }) {
                            let camo = [tiers.tier1, tiers.tier2, tiers.tier3][tier - 1]
                            onCompletionist.append((Suggestion(
                                weaponId: weaponId,
                                title: weapon.name.resolved(),
                                subtitle: String(format: "mw4.ui.suggestion.next_camo".localized(), camo.name),
                                highlight: camo.color,
                                gradient: camo.gradient
                            ), Self.completionistStepCount + tier))
                        }
                        continue
                    }
                    // Only once it can be worked on: Platinum waits for the
                    // class's Golds, Harmonic Break for every Platinum
                    guard isCompletionistAvailable(mode: mode, weaponId: weaponId, step: next) else { continue }
                    onCompletionist.append((Suggestion(
                        weaponId: weaponId,
                        title: weapon.name.resolved(),
                        subtitle: String(format: "mw4.ui.suggestion.next_camo".localized(), steps[next].name),
                        highlight: steps[next].color,
                        gradient: steps[next].gradient
                    ), next))
                } else {
                    let remaining = remainingCamoCount(weaponId: weaponId, mode: mode)
                    guard remaining > 0 else { continue }
                    onCamoList.append((Suggestion(
                        weaponId: weaponId,
                        title: weapon.name.resolved(),
                        subtitle: "\(remaining) camo\(remaining == 1 ? "" : "s") to complete",
                        highlight: nil
                    ), remaining))
                }
            }
        }

        onCompletionist.sort { $0.1 > $1.1 }
        onCamoList.sort { $0.1 < $1.1 }
        return Array((onCompletionist.map(\.0) + onCamoList.map(\.0)).prefix(limit))
    }

    /// Called right after a camo or level change with whether the weapon's
    /// camo list was finished *before* it. Finishing the list opens Gold.
    func checkMilestone(weaponId: Int, mode: String, wasGold: Bool) {
        guard !wasGold, allCamosComplete(weaponId: weaponId, mode: mode) else { return }
        let weaponName = weapon(id: weaponId)?.name.resolved() ?? "This weapon"
        announce(title: "mw4.ui.milestone.camos_complete_title".localized(),
                 subtitle: "\(weaponName).", titleGradient: .gold, icon: "medal.fill", weaponId: weaponId)

        // Finishing a weapon is the high point worth asking on. The gate
        // reads the real count, and nothing is spent until the prompt is
        // actually handed over (see ReviewPrompt / ContentView).
        if ReviewPrompt.shouldAsk(weaponsComplete: weaponsWithBaseCamosComplete) {
            raiseReviewRequest()
        }
    }

    /// Called right after a Completionist change with the state from before
    /// it. One tap can earn this weapon's step, unlock the final camo on
    /// several weapons at once (the mode's Harmonic Break count just reached
    /// the number needed), reach a Mastery tier, and reach 100%+: announced
    /// in that order, each only if it is new.
    func checkCompletionistMilestone(mode: String, weaponId: Int, before: CompletionistSnapshot) {
        guard let appMode = AppMode(rawValue: mode),
              let weaponName = weapon(id: weaponId)?.name.resolved() else { return }
        let completionist = appMode.completionist
        let icons = ["medal.fill", "seal.fill", "waveform.path"]

        for step in (0..<Self.completionistStepCount).reversed()
        where !before.steps[step] && isCompletionistComplete(mode: mode, weaponId: weaponId, step: step) {
            let camo = completionist.steps[step]
            announce(title: String(format: "mw4.ui.milestone.unlocked_title".localized(), camo.name),
                     subtitle: weaponName, titleGradient: camo.gradient, icon: icons[step], weaponId: weaponId)
            break
        }

        let finals = finalCamoCount(mode: mode)
        if finals > before.finalCamoCount {
            let gained = finals - before.finalCamoCount
            let one = gained == 1 && hasFinalCamo(mode: mode, weaponId: weaponId)
            announce(title: String(format: "mw4.ui.milestone.unlocked_title".localized(), completionist.final.name),
                     subtitle: one
                        ? weaponName
                        : String(format: "mw4.ui.milestone.final_many".localized(), gained),
                     titleGradient: completionist.final.gradient, icon: "sparkles", weaponId: one ? weaponId : nil)
        }

        let tiers = appMode.masteryCamos
        let tierCamos = [tiers.tier1, tiers.tier2, tiers.tier3]
        // A challenge Mastery tier on this weapon.
        for tier in (1...3).reversed()
        where !before.weaponMastery[tier - 1] && isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier) {
            announce(title: String(format: "mw4.ui.milestone.unlocked_title".localized(), tierCamos[tier - 1].name),
                     subtitle: weaponName, titleGradient: tierCamos[tier - 1].gradient, icon: "diamond.fill", weaponId: weaponId)
            break
        }
        for tier in (1...3).reversed() where !before.mastery[tier - 1] && isMasteryAchieved(mode: mode, tier: tier) {
            announce(title: String(format: "mw4.ui.milestone.unlocked_title".localized(), tierCamos[tier - 1].name),
                     subtitle: tier == 3
                        ? "mw4.ui.milestone.tier3_subtitle".localized()
                        : masteryKind(mode: mode, tier: tier) == .mode
                        ? "mw4.ui.milestone.mode_mastery_subtitle".localized()
                        : String(format: "mw4.ui.milestone.mastery_subtitle".localized(),
                                 masteryProgress(mode: mode, tier: tier).total,
                                 masteryKind(mode: mode, tier: tier) == .challenge ? tierCamos[tier - 1].name : appMode.lastCompletionist.name),
                     titleGradient: tierCamos[tier - 1].gradient, icon: tier == 3 ? "star.fill" : "diamond.fill")
            break
        }

        if !before.is100Plus, is100PlusAchieved(mode: mode) {
            announce(title: "mw4.ui.milestone.100_plus_title".localized(),
                     subtitle: String(format: "mw4.ui.milestone.100_plus_subtitle".localized(),
                                      masteryKind(mode: mode, tier: 3) == .challenge ? tierCamos[2].name : appMode.lastCompletionist.name),
                     titleGradient: .platinum, icon: "crown.fill")
        }
    }

    private func announce(title: String, subtitle: String, titleGradient: [Color], icon: String, weaponId: Int? = nil) {
        let banner = MilestoneBanner(id: UUID(), title: title, subtitle: subtitle, titleGradient: titleGradient, icon: icon,
                                     weaponId: weaponId)
        milestoneBanner = banner
        Haptics.milestone()
        Task { [weak self] in
            // Long enough to reach its Share button
            try? await Task.sleep(nanoseconds: Self.bannerNanoseconds)
            if self?.milestoneBanner?.id == banner.id {
                self?.milestoneBanner = nil
            }
        }
    }
}
