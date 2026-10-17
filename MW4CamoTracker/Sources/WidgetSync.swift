import SwiftUI
import WidgetKit

/// Keeps the widgets' snapshot (`WidgetSnapshot`) in step with the app:
/// rebuilt shortly after any change to progress, the pin, the modes played or
/// the language, written to the App Group only when it actually differs, and
/// the widgets told to redraw.
extension TrackerViewModel {
    func refreshWidgets() {
        widgetTask?.cancel()
        widgetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self, let snapshot = self.widgetSnapshot(),
                  let url = WidgetSnapshot.fileURL else { return }
            if WidgetSnapshot.load() == snapshot { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func widgetSnapshot() -> WidgetSnapshot? {
        guard catalog != nil else { return nil }
        let defaults = UserDefaults.standard
        let playedRaw = defaults.string(forKey: AppMode.playedKey) ?? ""
        let played = AppMode.played(playedRaw)
        let start = AppMode.start(defaults.string(forKey: AppMode.startKey) ?? "", played: playedRaw)
        let weapons = allWeapons.count

        let modes = played.map { mode -> WidgetSnapshot.Mode in
            let raw = mode.rawValue
            let camos = mode.completionistCamos
            let steps = camos.enumerated().map { index, camo in
                WidgetSnapshot.Step(name: camo.name, done: completionistCount(mode: raw, step: index),
                                    total: weapons, colorHex: camo.color.hexString)
            }
            let tiers = mode.masteryCamos
            let mastery = [tiers.tier1, tiers.tier2, tiers.tier3].enumerated().map { index, camo in
                let tier = index + 1
                let progress = masteryProgress(mode: raw, tier: tier)
                let achieved = isMasteryAchieved(mode: raw, tier: tier)
                return WidgetSnapshot.Step(name: camo.name,
                                           done: achieved ? max(progress.total, 1) : min(progress.done, progress.total),
                                           total: max(progress.total, 1), colorHex: camo.color.hexString)
            }
            return WidgetSnapshot.Mode(id: raw, name: mode.displayNameKey.localized(), accentHex: mode.accent.hexString,
                                       fraction: trueCompletionFraction(mode: raw), weaponCount: weapons,
                                       steps: steps, mastery: mastery)
        }

        let pinned = pinnedWeaponId.flatMap(weapon(id:)).map { weapon in
            pinnedSnapshot(weapon, mode: start)
        }
        let overall = modes.isEmpty ? 0 : modes.map(\.fraction).reduce(0, +) / Double(modes.count)
        return WidgetSnapshot(modes: modes, pinned: pinned, overall: overall,
                              overallLabel: "mw4.ui.stats.overall".localized(),
                              pinPrompt: "mw4.widget.pin_prompt".localized(),
                              allDoneLabel: "mw4.widget.all_done".localized())
    }

    /// The pinned weapon in `mode`: its camo count and the next thing to
    /// earn on it, a camo with its challenge, else the next Completionist
    /// camo.
    private func pinnedSnapshot(_ weapon: WeaponEntry, mode: AppMode) -> WidgetSnapshot.Pinned {
        let raw = mode.rawValue
        let counts = camoCounts(weaponId: weapon.weaponId, mode: raw)
        var nextName: String?
        var nextDetail: String?
        var nextDone = 0
        var nextTotal = 1
        let leaves = camos(weaponId: weapon.weaponId, mode: raw).flatMap(leafItems)
        if let camo = leaves.first(where: { !isCamoComplete(mode: raw, weaponId: weapon.weaponId, camo: $0) }) {
            nextName = camo.name.resolved()
            if let requirement = camo.requirement {
                nextDetail = requirement.description.resolved()
                nextTotal = max(requirement.amount, 1)
                nextDone = camoAmount(mode: raw, weaponId: weapon.weaponId, camo: camo)
            } else if let level = militaryLevel(mode: raw, weaponId: weapon.weaponId, camo: camo) {
                nextDetail = String(format: "mw4.ui.camo_level_reach".localized(), level)
                nextTotal = level
                nextDone = min(self.level(for: weapon.weaponId), level)
            }
        } else if let step = (0..<Self.completionistStepCount).first(where: {
            !isCompletionistComplete(mode: raw, weaponId: weapon.weaponId, step: $0)
        }) {
            nextName = mode.completionistCamos[step].name
        }
        return WidgetSnapshot.Pinned(
            weaponId: weapon.weaponId, name: weapon.name.resolved(),
            category: category(containingWeaponId: weapon.weaponId)?.name.resolved() ?? "",
            mode: raw, modeName: mode.displayNameKey.localized(), accentHex: mode.accent.hexString,
            camosDone: counts.done, camosTotal: counts.total,
            nextName: nextName, nextDetail: nextDetail, nextDone: nextDone, nextTotal: nextTotal)
    }
}

extension Color {
    /// "#RRGGBB" for the widgets, which get colours through the snapshot.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
