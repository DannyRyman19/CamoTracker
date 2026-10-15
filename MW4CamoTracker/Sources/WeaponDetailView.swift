import SwiftUI

/// The level control at the top is global — change it here while looking at
/// Multiplayer and it reads the same when you check this weapon from DMZ,
/// and it opens level-gated camos in every mode at once. The camo list and
/// Mastery below it are specific to whichever mode tab got you here.
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
    @State private var width: CGFloat = 0

    @ViewBuilder private var headerSection: some View {
        // Camo tracking is the actual point of this app — the hero
        // image (a placeholder; no real art exists) and the level
        // control are context, not content, so both are compact and
        // share one card instead of each claiming a full screen's
        // worth of attention before the Camos list even starts.
        Section {
            VStack(alignment: .leading, spacing: 12) {
                WeaponHeroImage(urlString: weapon.imageURL)

                titleBlock(nameSize: 20)

                Divider().overlay(Color.appInkMuted.opacity(0.2))

                CompactLevelRow(mode: mode, weapon: weapon)
            }
            .padding(12)
            .borderedCard()
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(Color.clear)
        }
        .listRowBackground(Color.appSurface)
    }

    /// The camo list split the way the game shows it: Military, then
    /// Special. Camos with no group (older data) stay one "Camos" list.
    private var camoGroups: [(title: String, camos: [ChallengeItem])] {
        var groups: [(key: String?, camos: [ChallengeItem])] = []
        for camo in camos {
            if let last = groups.indices.last, groups[last].key == camo.group {
                groups[last].camos.append(camo)
            } else {
                groups.append((camo.group, [camo]))
            }
        }
        return groups.map { group in
            let title: String
            switch group.key {
            case "military": title = "mw4.ui.section.military".localized()
            case "special": title = "mw4.ui.section.special".localized()
            default: title = "mw4.ui.section.camos".localized()
            }
            return (title, group.camos)
        }
    }

    private var completionistTitle: String {
        "\(mode.displayNameKey.localized()) \("mw4.ui.section.completionist".localized())"
    }

    private var masteryTitle: String {
        "\(mode.displayNameKey.localized()) \("mw4.ui.section.mastery".localized())"
    }

    @ViewBuilder private var challengeSections: some View {
        if camos.isEmpty {
            noCamoData
            .listRowBackground(Color.appSurface)
        } else {
            ForEach(camoGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.camos) { camo in
                        camoRow(camo)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
        }

        // Finishing the camo list above opens this weapon's Completionist
        // camos, and those feed the mode's Mastery camos.
        Section(completionistTitle) {
            ForEach(0..<TrackerViewModel.completionistStepCount, id: \.self) { step in
                CompletionistStepRow(mode: mode, weapon: weapon, step: step)
            }
            FinalCamoRow(mode: mode, weapon: weapon)
        }
        .listRowBackground(Color.appSurface)

        Section(masteryTitle) {
            ForEach(1...3, id: \.self) { tier in
                MasteryModeRow(mode: mode, tier: tier)
            }
        }
        .listRowBackground(Color.appSurface)
    }

    private var noCamoData: some View {
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
    }

    private func titleBlock(nameSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let category {
                Text(category.name.resolved())
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appInkMuted)
            }
            Text(weapon.name.resolved())
                .font(.hitmarker(nameSize))
                .foregroundStyle(Color.appInk)
            AcquiredByLabel(weapon: weapon)
        }
    }

    private func camoRow(_ camo: ChallengeItem) -> some View {
        ChallengeRow(
            item: camo,
            accent: mode.accent,
            amount: viewModel.camoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
            isDone: viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
            isAvailable: viewModel.isCamoAvailable(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
            lockedReason: camo.unlockLevel.map { String(format: "mw4.ui.camo_level_locked".localized(), $0) },
            detail: viewModel.isEarnedByLevel(camo) ? camo.unlockLevel.map { String(format: "mw4.ui.camo_level_earned".localized(), $0) } : nil,
            onToggle: { viewModel.toggleCamo(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo) },
            onSetAmount: { viewModel.setCamoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo, amount: $0) }
        )
    }

    private static let rowInsets = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

    /// iPad: the weapon's art beside its name, level and Prestige in one
    /// wide card, then the camos and the Mastery trio as tiles, so the
    /// screen is filled rather than one phone-width column on a big canvas.
    /// A camo tile needs about 400pt to keep its sentence and its stepper on
    /// good terms, so an unfolded iPhone Duo held upright (about 670pt) gets
    /// the wide header over full-width tiles, and only wider screens a grid.
    private var tileColumns: Int { width >= 1250 ? 3 : (width >= 840 ? 2 : 1) }
    private var masteryInOneRow: Bool { width >= 1000 }

    @ViewBuilder private var wideSections: some View {
        let columns = tileColumns
        HStack(alignment: .center, spacing: 20) {
            WeaponHeroImage(urlString: weapon.imageURL, height: 210)
            VStack(alignment: .leading, spacing: 14) {
                titleBlock(nameSize: 28)
                Divider().overlay(Color.appInkMuted.opacity(0.2))
                CompactLevelRow(mode: mode, weapon: weapon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .borderedCard()
        .listRowInsets(Self.rowInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if camos.isEmpty {
            noCamoData
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(camoGroups, id: \.title) { group in
                Section(group.title) {
                    tileRows(group.camos.map { camo in AnyView(camoRow(camo)) }, columns: columns)
                }
            }
        }

        Section(completionistTitle) {
            tileRows((0..<TrackerViewModel.completionistStepCount).map { step in
                AnyView(CompletionistStepRow(mode: mode, weapon: weapon, step: step))
            } + [AnyView(FinalCamoRow(mode: mode, weapon: weapon))], columns: masteryInOneRow ? 4 : columns)
        }

        Section(masteryTitle) {
            tileRows((1...3).map { tier in AnyView(MasteryModeRow(mode: mode, tier: tier)) },
                     columns: masteryInOneRow ? 3 : columns)
        }
    }

    /// Rows of `columns` tiles, the last row padded so tiles keep one width.
    @ViewBuilder private func tileRows(_ tiles: [AnyView], columns: Int) -> some View {
        ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<columns, id: \.self) { offset in
                    if start + offset < tiles.count {
                        tiles[start + offset].modifier(DetailTile())
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .listRowInsets(Self.rowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            if WideLayout.columns(for: width) >= 2 {
                List { wideSections }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
            } else {
                List {
                    headerSection
                    challengeSections
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
        .readingWidth($width)
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

/// Gold, Platinum or Harmonic Break on this weapon: its own challenge
/// (which can differ by weapon category), as a `ChallengeRow` like the camo
/// list above, so it locks, ticks and counts the same way.
private struct CompletionistStepRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    let step: Int
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camo: MasteryCamo { mode.completionist.steps[step] }

    private var item: ChallengeItem {
        ChallengeItem(
            itemId: -(step + 1),
            name: LocalizedText(camo.name),
            imageURL: nil,
            tier: nil,
            unlockLevel: nil,
            requirement: viewModel.completionistRequirement(mode: mode.rawValue, weaponId: weapon.weaponId, step: step),
            children: []
        )
    }

    /// What still stands in the way: this weapon's own step before first,
    /// then the class- or mode-wide gate.
    private var lockedReason: String {
        let before = step == 0 ? nil : mode.completionist.steps[step - 1].name
        let ownDone = step == 0
            ? viewModel.allCamosComplete(weaponId: weapon.weaponId, mode: mode.rawValue)
            : viewModel.isCompletionistComplete(mode: mode.rawValue, weaponId: weapon.weaponId, step: step - 1)
        guard ownDone else {
            return before.map { String(format: "mw4.ui.completionist.locked_previous".localized(), $0) }
                ?? "mw4.ui.completionist.locked_camos".localized()
        }
        switch viewModel.completionistGate(mode: mode.rawValue, step: step) {
        case .weapon:
            return "mw4.ui.locked".localized()
        case .category:
            let className = viewModel.category(containingWeaponId: weapon.weaponId)?.name.resolved() ?? ""
            return before.map { String(format: "mw4.ui.completionist.locked_class".localized(), $0, className) }
                ?? String(format: "mw4.ui.completionist.locked_class_camos".localized(), className)
        case .mode:
            let progress = viewModel.completionistModeGateProgress(mode: mode.rawValue, step: step)
            return String(format: "mw4.ui.completionist.locked_mode".localized(), before ?? "", progress.total, progress.done)
        }
    }

    var body: some View {
        ChallengeRow(
            item: item,
            accent: camo.color,
            amount: viewModel.completionistAmount(mode: mode.rawValue, weaponId: weapon.weaponId, step: step),
            isDone: viewModel.isCompletionistComplete(mode: mode.rawValue, weaponId: weapon.weaponId, step: step),
            isAvailable: viewModel.isCompletionistAvailable(mode: mode.rawValue, weaponId: weapon.weaponId, step: step),
            lockedReason: lockedReason,
            titleGradient: camo.gradient,
            onToggle: { viewModel.toggleCompletionist(mode: mode.rawValue, weaponId: weapon.weaponId, step: step) },
            onSetAmount: { viewModel.setCompletionistAmount(mode: mode.rawValue, weaponId: weapon.weaponId, step: step, amount: $0) }
        )
    }
}

/// The final Completionist camo (Divergence in Multiplayer). Read-only: it
/// has no challenge, the weapon earns it once it has its own Harmonic Break
/// and the mode has enough Harmonic Breaks overall.
private struct FinalCamoRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camo: MasteryCamo { mode.completionist.final }
    private var harmonicBreak: MasteryCamo { mode.completionist.steps[2] }
    private var achieved: Bool { viewModel.hasFinalCamo(mode: mode.rawValue, weaponId: weapon.weaponId) }

    private var detail: String {
        let needed = viewModel.harmonicBreaksNeeded(mode: mode.rawValue)
        let done = viewModel.harmonicBreakCount(mode: mode.rawValue)
        if !viewModel.isCompletionistComplete(mode: mode.rawValue, weaponId: weapon.weaponId, step: 2) {
            return needed > 1
                ? String(format: "mw4.ui.completionist.final_locked_count".localized(), harmonicBreak.name, needed, min(done, needed))
                : String(format: "mw4.ui.completionist.locked_previous".localized(), harmonicBreak.name)
        }
        return String(format: "mw4.ui.completionist.final_count".localized(), min(done, max(needed, 1)), max(needed, 1), harmonicBreak.name)
    }

    var body: some View {
        StatusRow(name: camo.name, achieved: achieved, color: camo.color, gradient: camo.gradient, detail: detail)
    }
}

/// One of the mode's three Mastery camos: earned once enough weapons have
/// the final Completionist camo. Mode-wide, so it reads the same on every
/// weapon in the mode.
private struct MasteryModeRow: View {
    let mode: AppMode
    let tier: Int
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camo: MasteryCamo {
        let tiers = mode.masteryCamos
        return [tiers.tier1, tiers.tier2, tiers.tier3][tier - 1]
    }

    var body: some View {
        let progress = viewModel.masteryProgress(mode: mode.rawValue, tier: tier)
        StatusRow(
            name: camo.name,
            achieved: viewModel.isMasteryAchieved(mode: mode.rawValue, tier: tier),
            color: camo.color,
            gradient: camo.gradient,
            detail: String(format: "mw4.ui.mastery.weapons_needed".localized(), progress.done, progress.total, mode.completionist.final.name)
        )
    }
}

/// A camo earned by reaching a count rather than by hand: a check once
/// earned, a lock until then, with the count under its name.
private struct StatusRow: View {
    let name: String
    let achieved: Bool
    let color: Color
    let gradient: [Color]
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: achieved ? 21 : 17))
                .foregroundStyle(achieved ? color : Color.appInkMuted.opacity(0.5))
                .frame(width: 21, height: 21)

            VStack(alignment: .leading, spacing: 4) {
                if achieved {
                    AnimatedGradientText(text: name, colors: gradient, font: .hitmarker(15))
                } else {
                    Text(name)
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInkMuted)
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .padding(.vertical, 5)
    }
}

/// A single-line level readout. Level opens the base camos below it (each
/// camo's `unlockLevel`, in every mode), so changing it here unlocks rows
/// straight away. Tap the number to type an exact level, +/- to nudge, MAX to jump to cap.
/// Under it, when the catalog defines any Weapon Prestige stages, a second
/// line steps through them: + once the current stage is maxed (level goes
/// back to 1), - to undo a mistaken tap.
private struct CompactLevelRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    @State private var showValueEntry = false
    @State private var valueText = ""

    private var level: Int { viewModel.level(for: weapon.weaponId) }
    private var maxLevel: Int { viewModel.maxLevel(for: weapon) }
    private var prestige: Int { viewModel.prestige(for: weapon.weaponId) }
    private var stageCount: Int { viewModel.prestigeStages.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            levelLine
            if stageCount > 0 {
                prestigeLine
            }
        }
        .alert("mw4.ui.set_level.title".localized(), isPresented: $showValueEntry) {
            TextField("mw4.ui.set_amount.field".localized(), text: $valueText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.save".localized()) {
                if let entered = Int(valueText) { viewModel.setLevel(entered, for: weapon) }
            }
        } message: {
            Text(String(format: "mw4.ui.set_level.message".localized(), 0, maxLevel))
        }
    }

    /// Stage pips and the current stage's name on the left; on the right one
    /// button named after the stage it moves to, so it reads as "go to
    /// Prestige 1" rather than a bare +. It only lights up once the current
    /// stage is maxed. The small undo beside it steps back a mistaken tap.
    private var prestigeLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("mw4.ui.prestige".localized())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appInkMuted)
                    HStack(spacing: 6) {
                        if stageCount <= 8 {
                            HStack(spacing: 3) {
                                ForEach(0..<stageCount, id: \.self) { index in
                                    Capsule()
                                        .fill(index < prestige ? mode.accent : Color.appInkMuted.opacity(0.25))
                                        .frame(width: 14, height: 5)
                                }
                            }
                        } else {
                            Text("\(prestige)/\(stageCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.appInkMuted)
                        }
                        Text(viewModel.prestigeName(for: weapon.weaponId) ?? "mw4.ui.prestige.none".localized())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(prestige > 0 ? mode.accent : Color.appInkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 8)

                if prestige > 0 {
                    Button {
                        withAnimation(.snappy) { viewModel.prestigeDown(weapon) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appInkMuted)
                            .frame(width: 28, height: 28)
                            .background(Circle().stroke(Color.appInkMuted.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("mw4.ui.prestige.undo".localized())
                }

                if prestige < stageCount {
                    let ready = viewModel.canPrestige(weapon)
                    Button {
                        withAnimation(.snappy) { viewModel.prestigeUp(weapon) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: ready ? "chevron.up.2" : "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(viewModel.prestigeStages[prestige].name.resolved())
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(ready ? Color.appBackground : Color.appInkMuted)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(ready ? mode.accent : Color.appInkMuted.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(mode.accent)
                }
            }
            if prestige < stageCount, level < maxLevel {
                Text(String(format: "mw4.ui.prestige.hint".localized(), maxLevel))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }

    /// The stepper, with a thin bar under it so how far through the current
    /// stage the weapon is reads at a glance.
    private var levelLine: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Longer in French and Spanish than the room beside the stepper
                // on a narrow header: shrink a little before truncating.
                Text("mw4.ui.weapon_level".localized())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                stepButton(systemName: "minus", enabled: level > 0, size: 26, accent: mode.accent) {
                    viewModel.setLevel(level - 1, for: weapon)
                }

                Button {
                    valueText = "\(level)"
                    showValueEntry = true
                } label: {
                    Text("\(level)/\(maxLevel)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(mode.accent)
                        .contentTransition(.numericText())
                        .frame(minWidth: 56)
                }
                .buttonStyle(.plain)

                stepButton(systemName: "plus", enabled: level < maxLevel, size: 26, accent: mode.accent) {
                    viewModel.setLevel(level + 1, for: weapon)
                }

                Button {
                    withAnimation(.snappy) { viewModel.setLevel(maxLevel, for: weapon) }
                } label: {
                    Text("mw4.ui.max".localized())
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(level == maxLevel ? Color.appInkMuted : mode.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Capsule().stroke(level == maxLevel ? Color.appInkMuted.opacity(0.3) : mode.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(level == maxLevel)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appInkMuted.opacity(0.2))
                    Capsule()
                        .fill(mode.accent)
                        .frame(width: maxLevel > 0 ? proxy.size.width * CGFloat(level) / CGFloat(maxLevel) : 0)
                }
            }
            .frame(height: 4)
            .animation(.snappy, value: level)
            .animation(.snappy, value: maxLevel)
        }
    }
}

/// A camo or Mastery row as a tile in the iPad grid: the same row, on its own
/// rounded surface, stretched so a row of tiles shares one height.
private struct DetailTile: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appSurface))
    }
}
