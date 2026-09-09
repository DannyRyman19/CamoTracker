import SwiftUI

/// The level control at the top is global — change it here while looking at
/// Multiplayer and it reads the same when you check this weapon from DMZ.
/// The camo list below it is specific to whichever mode tab got you here.
struct WeaponDetailView: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camos: [ChallengeItem] { viewModel.camos(weaponId: weapon.weaponId, mode: mode.rawValue) }
    private var category: WeaponCategory? { viewModel.category(containingWeaponId: weapon.weaponId) }

    private var isPinned: Bool { viewModel.pinnedWeaponId == weapon.weaponId }

    /// Hosted here rather than inside the toolbar's menu: a `.alert` attached
    /// to `ToolbarItem` content does not reliably present.
    @State private var askingMaxLevel = false
    @State private var maxLevelText = ""
    @State private var askingUnlockLevel = false
    @State private var unlockLevelText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                // Camo tracking is the actual point of this app — the hero
                // image (a placeholder; no real art exists) and the level
                // control are context, not content, so both are compact and
                // share one card instead of each claiming a full screen's
                // worth of attention before the Camos list even starts.
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        WeaponHeroImage(urlString: weapon.imageURL)

                        VStack(alignment: .leading, spacing: 3) {
                            if let category {
                                Text(category.name.resolved())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.appInkMuted)
                            }
                            Text(weapon.name.resolved())
                                .font(.hitmarker(20))
                                .foregroundStyle(Color.appInk)
                            AcquiredByLabel(weapon: weapon)
                        }

                        Divider().overlay(Color.appInkMuted.opacity(0.2))

                        CompactLevelRow(mode: mode, weapon: weapon)
                    }
                    .padding(12)
                    .borderedCard()
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.appSurface)

                if camos.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 21))
                            .foregroundStyle(Color.appInkMuted)
                        Text(String(format: "mw4.ui.no_camo_data".localized(), mode.displayNameKey.localized()))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appInkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.appSurface)
                } else {
                    Section("mw4.ui.section.camos".localized()) {
                        ForEach(camos) { camo in
                            ChallengeRow(
                                item: camo,
                                accent: mode.accent,
                                amount: viewModel.camoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
                                isDone: viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
                                isAvailable: viewModel.isCamoAvailable(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
                                onToggle: { viewModel.toggleCamo(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo) },
                                onSetAmount: { viewModel.setCamoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo, amount: $0) }
                            )
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                // Shown in every mode, even DMZ (which has no per-weapon camo
                // track of its own) — the mode-wide capstone still applies,
                // so every weapon's page reflects where that mode's grind
                // actually stands, not just weapons with a base camo track.
                Section("\(mode.displayNameKey.localized()) \("mw4.ui.section.mastery".localized())") {
                    if !camos.isEmpty {
                        MasteryTierRow(mode: mode, weapon: weapon, tier: 1)
                        MasteryTierRow(mode: mode, weapon: weapon, tier: 2)
                    }
                    MasteryTier3Row(mode: mode, weapon: weapon)
                }
                .listRowBackground(Color.appSurface)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(weapon.name.resolved())
        .alert("mw4.ui.report.max_level".localized(), isPresented: $askingMaxLevel) {
            TextField("mw4.ui.report.max_level.field".localized(), text: $maxLevelText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            // An empty field still sends: a vaguer report beats no report.
            Button("mw4.ui.report.send".localized()) {
                if let url = SupportMail.url(kind: .maxLevel, weapon: weapon, mode: mode,
                                             category: category?.name.resolved(),
                                             correctedMaxLevel: Int(maxLevelText)) {
                    openURL(url)
                }
            }
        } message: {
            Text(String(format: "mw4.ui.report.max_level.message".localized(), weapon.maxLevel))
        }
        .alert("mw4.ui.report.unlock".localized(), isPresented: $askingUnlockLevel) {
            TextField("mw4.ui.report.unlock.field".localized(), text: $unlockLevelText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.report.send".localized()) {
                if let url = SupportMail.url(kind: .unlock, weapon: weapon, mode: mode,
                                             category: category?.name.resolved(),
                                             unlock: .playerLevel(Int(unlockLevelText))) {
                    openURL(url)
                }
            }
        } message: {
            Text(String(format: "mw4.ui.report.unlock.message".localized(),
                        weapon.unlockLevel.map(String.init) ?? "-"))
        }
        .toolbar {
            // Camo data is hand-entered from a game that keeps changing, so a
            // pre-filled report is worth reaching easily. At the foot of the
            // camo list it was several screens of scrolling away.
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportIssueMenu(weapon: weapon, mode: mode,
                                category: category?.name.resolved(), camos: camos,
                                compact: true,
                                onRequestMaxLevel: {
                                    maxLevelText = ""
                                    askingMaxLevel = true
                                },
                                onRequestUnlockLevel: {
                                    unlockLevelText = ""
                                    askingUnlockLevel = true
                                })
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if isPinned {
                        viewModel.unpin()
                    } else {
                        viewModel.pin(weaponId: weapon.weaponId)
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel((isPinned ? "mw4.ui.unpin" : "mw4.ui.pin").localized())
            }
        }
    }
}

/// This weapon's own tier1 or tier2 Mastery challenge — the piece that was
/// missing entirely before: every weapon needs its own trackable Mastery
/// camo, not just an abstract account-wide counter. Reuses `ChallengeRow`'s
/// lock/available/tap-to-type machinery by wrapping the tier's requirement
/// as a synthetic `ChallengeItem`, same UI language as the camo list above.
private struct MasteryTierRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    let tier: Int
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camo: MasteryCamo {
        let tiers = mode.masteryCamos
        return tier == 1 ? tiers.tier1 : tiers.tier2
    }

    private var isAvailable: Bool {
        tier == 1
            ? viewModel.isWeaponMasteryTier1Available(weaponId: weapon.weaponId, mode: mode.rawValue)
            : viewModel.isWeaponMasteryTier2Available(weaponId: weapon.weaponId, mode: mode.rawValue)
    }

    private var item: ChallengeItem {
        let requirement = camo.requirement
        return ChallengeItem(
            itemId: -tier,
            name: LocalizedText(camo.name),
            imageURL: nil,
            tier: nil,
            requirement: requirement.map { Requirement(amount: $0.amount, unit: "headshots", description: LocalizedText($0.description(camoName: camo.name))) },
            children: []
        )
    }

    private var amount: Int { viewModel.weaponMasteryAmount(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier) }

    var body: some View {
        ChallengeRow(
            item: item,
            accent: camo.color,
            amount: amount,
            isDone: viewModel.isWeaponMasteryComplete(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier),
            isAvailable: isAvailable,
            lockedReason: tier == 2 ? String(format: "mw4.ui.mastery_tier2_locked".localized(), mode.masteryCamos.tier1.name) : nil,
            titleGradient: camo.gradient,
            // Tap the circle to instantly toggle full/none — the same quick-
            // complete gesture every other checklist in this app supports;
            // this row was silently missing it before.
            onToggle: {
                let full = camo.requirement?.amount ?? 0
                viewModel.setWeaponMasteryAmount(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier, amount: amount >= full ? 0 : full)
            },
            onSetAmount: { viewModel.setWeaponMasteryAmount(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier, amount: $0) }
        )
    }
}

/// The mode-wide capstone (tier3) — read-only, since it isn't earned per
/// weapon, but shown on every weapon's page (all modes, even DMZ) so this
/// screen always reflects where that mode's whole Mastery chain stands.
private struct MasteryTier3Row: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camo: MasteryCamo { mode.masteryCamos.tier3 }
    private var modeAchieved: Bool { viewModel.isMasteryTier3Achieved(mode: mode.rawValue) }
    /// Mode-wide achievement alone doesn't make *this weapon's* row read as
    /// achieved — with the launch-roster-sized capstone gate, the mode can
    /// hit tier3 via 19 other weapons while a brand-new DLC weapon (this
    /// one) hasn't itself finished its own tier2 yet, and showing "Mastery
    /// complete" on a weapon nobody's touched would be actively misleading.
    /// DMZ has no per-weapon Mastery track to check against, so it keeps the
    /// mode-wide-only rule.
    private var achieved: Bool {
        guard viewModel.modeHasWeaponTrack(mode.rawValue) else { return modeAchieved }
        return modeAchieved && viewModel.isWeaponMasteryComplete(mode: mode.rawValue, weaponId: weapon.weaponId, tier: 2)
    }
    private var progress: (done: Int, total: Int) { viewModel.masteryTier2Progress(mode: mode.rawValue) }
    private var lockedReason: String {
        modeAchieved
            ? "mw4.ui.mastery_tier3_locked_weapon".localized()
            : String(format: "mw4.ui.mastery_tier3_locked".localized(), mode.displayNameKey.localized(), mode.masteryCamos.tier2.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: achieved ? 21 : 17))
                .foregroundStyle(achieved ? camo.color : Color.appInkMuted.opacity(0.5))
                .frame(width: 21, height: 21)

            VStack(alignment: .leading, spacing: 4) {
                if achieved {
                    AnimatedGradientText(text: camo.name, colors: camo.gradient, font: .hitmarker(15))
                } else {
                    Text(camo.name)
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInkMuted)
                }
                Text(achieved ? "\(progress.done)/\(progress.total) \("mw4.ui.weapons_unit".localized())" : lockedReason)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .padding(.vertical, 5)
    }
}

/// A single-line level readout instead of the old full-width stepper card —
/// leveling doesn't gate any camo or Mastery progress, so it doesn't need
/// the same visual weight as the checklist that actually does. Still every
/// bit as functional: tap the number to type an exact level, +/- to nudge,
/// MAX to jump straight to cap.
private struct CompactLevelRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    @State private var showValueEntry = false
    @State private var valueText = ""

    private var level: Int { viewModel.level(for: weapon.weaponId) }

    var body: some View {
        HStack(spacing: 10) {
            Text("mw4.ui.weapon_level".localized())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appInkMuted)

            Spacer(minLength: 8)

            stepButton(systemName: "minus", enabled: level > 0, size: 24, accent: mode.accent) {
                viewModel.setLevel(level - 1, for: weapon)
            }

            Button {
                valueText = "\(level)"
                showValueEntry = true
            } label: {
                Text("\(level)/\(weapon.maxLevel)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(mode.accent)
                    .frame(minWidth: 56)
            }
            .buttonStyle(.plain)

            stepButton(systemName: "plus", enabled: level < weapon.maxLevel, size: 24, accent: mode.accent) {
                viewModel.setLevel(level + 1, for: weapon)
            }

            Button("mw4.ui.max".localized()) {
                viewModel.setLevel(weapon.maxLevel, for: weapon)
            }
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(mode.accent)
            .opacity(level == weapon.maxLevel ? 0.35 : 1)
            .disabled(level == weapon.maxLevel)
        }
        .alert("mw4.ui.set_level.title".localized(), isPresented: $showValueEntry) {
            TextField("mw4.ui.set_amount.field".localized(), text: $valueText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.save".localized()) {
                if let entered = Int(valueText) { viewModel.setLevel(entered, for: weapon) }
            }
        } message: {
            Text(String(format: "mw4.ui.set_level.message".localized(), 0, weapon.maxLevel))
        }
    }
}
