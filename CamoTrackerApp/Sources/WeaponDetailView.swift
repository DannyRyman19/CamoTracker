import SwiftUI

/// The level control at the top is global — change it here while looking at
/// Multiplayer and it reads the same when you check this weapon from DMZ,
/// and it opens level-gated camos in every mode at once. The camo list and
/// Mastery below it are specific to whichever mode tab got you here.
struct WeaponDetailView: View {
    /// The mode whose challenge counts and Mastery this screen shows. Camos
    /// are one track per weapon across modes, so switching it changes the
    /// numbers and wording, never what's ticked.
    @State private var mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    init(mode: AppMode, weapon: WeaponEntry) {
        _mode = State(initialValue: mode)
        self.weapon = weapon
    }

    /// Multiplayer / DMZ (and Warzone once it's shown): which mode's counts.
    @ViewBuilder private var modeSwitch: some View {
        if viewModel.visibleModes.count > 1 {
            // A dropdown like the home title's, so it doesn't stack a second
            // segmented bar on the tabs below it
            HStack(spacing: 8) {
                Text("mw4.ui.counts_for".localized())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
                Menu {
                    Picker("mw4.ui.counts_for".localized(), selection: $mode) {
                        ForEach(viewModel.visibleModes) { m in
                            Label(m.displayNameKey.localized(), systemImage: m.symbol).tag(m)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(mode.displayNameKey.localized())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.appInk)
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(mode.accent)
                    }
                }
                .accessibilityLabel("mw4.ui.counts_for".localized())
                Spacer(minLength: 0)
            }
        }
    }

    /// The switch as its own row, just above the tabs it changes.
    @ViewBuilder private var modeSwitchRow: some View {
        if viewModel.visibleModes.count > 1 {
            modeSwitch
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 2, trailing: 14))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// Open or shut for every weapon: someone hunting Prestige camos wants
    /// them open on the next gun too.
    @AppStorage("mw4.prestigeCamosOpen") private var prestigeCamosOpen = false

    /// The Weapon Prestige camos, under the Prestige control that earns
    /// them: a one-line count with their swatches, opening to the rows.
    /// On iPad it spans the card under the art, the rows `columns` across.
    @ViewBuilder private func prestigeCamosBlock(columns: Int = 1) -> some View {
        let count = viewModel.prestigeCamos.count
        if count > 0 {
            let done = viewModel.prestigeCamos.indices.filter {
                viewModel.isPrestigeCamoComplete(weaponId: weapon.weaponId, index: $0)
            }.count
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Color.appInkMuted.opacity(0.2))
                Button {
                    Haptics.step()
                    withAnimation(.snappy) { prestigeCamosOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("mw4.ui.prestige_camos".localized())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appInkMuted)
                        Spacer(minLength: 8)
                        Text("\(done)/\(count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(done == count ? mode.accent : Color.appInk)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appInkMuted)
                            .rotationEffect(.degrees(prestigeCamosOpen ? 90 : 0))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue("\(done)/\(count)")

                if prestigeCamosOpen {
                    let indices = Array(viewModel.prestigeCamos.indices)
                    ForEach(Array(stride(from: 0, to: indices.count, by: columns)), id: \.self) { start in
                        HStack(alignment: .top, spacing: 20) {
                            ForEach(start..<start + columns, id: \.self) { index in
                                if index < indices.count {
                                    prestigeCamoRow(index).frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

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

                titleBlock

                if !viewModel.quickTick {
                    Divider().overlay(Color.appInkMuted.opacity(0.2))

                    CompactLevelRow(mode: mode, weapon: weapon)
                }

                prestigeCamosBlock()
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

    /// The parts of this screen the picker switches between: each camo
    /// group (Military, Special), then Completionist, then Mastery.
    /// The mode's camos (Military and Special under their own headers),
    /// its Completionist camos, then Mastery. The Prestige camos are the
    /// same in every mode, so they sit in the card up top by the Prestige
    /// control instead.
    private enum Part: Hashable {
        case camos
        case completionist
        case mastery
    }

    private var parts: [(part: Part, title: String)] {
        [(.camos, "mw4.ui.section.camos".localized()),
         (.completionist, "mw4.ui.section.completionist".localized()),
         (.mastery, "mw4.ui.section.mastery".localized())]
    }

    /// Picked by hand, else the first part with something still to do.
    @State private var pickedPart: Part?

    private var shownPart: Part {
        if let pickedPart, parts.contains(where: { $0.part == pickedPart }) { return pickedPart }
        if camos.contains(where: { !viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: $0) }) {
            return .camos
        }
        return viewModel.hasLastCompletionist(mode: mode.rawValue, weaponId: weapon.weaponId) ? .mastery : .completionist
    }

    private var partPicker: some View {
        Picker("mw4.ui.section.camos".localized(), selection: Binding(get: { shownPart }, set: { if $0 != shownPart { Haptics.step() }; pickedPart = $0 })) {
            ForEach(parts, id: \.part) { entry in
                Text(entry.title).tag(entry.part)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// iPhone: one part at a time, chosen with the picker above it, rather
    /// than Military, Special, Completionist and Mastery in one long scroll.
    @ViewBuilder private var challengeSections: some View {
        if camos.isEmpty {
            noCamoData
            .listRowBackground(Color.appSurface)
        }

        modeSwitchRow
        partPicker

        if shownPart == .camos {
            // Military and Special, each under its own header.
            ForEach(camoGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.camos) { camo in
                        camoRow(camo)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
        }

        Section {
            switch shownPart {
            case .camos:
                EmptyView()
            case .completionist:
                // Finishing the camo list opens this weapon's Completionist
                // camos, and those feed the mode's Mastery camos.
                ForEach(0..<TrackerViewModel.completionistStepCount, id: \.self) { step in
                    CompletionistStepRow(mode: mode, weapon: weapon, step: step)
                }
                if mode.hasFinalCamo {
                    FinalCamoRow(mode: mode, weapon: weapon)
                }
            case .mastery:
                ForEach(1...3, id: \.self) { tier in
                    masteryRow(tier)
                }
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

    /// Class and how it's acquired. The name itself is the screen's title,
    /// so it isn't repeated here.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let category {
                Text(category.name.resolved())
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appInkMuted)
            }
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
            lockedReason: camo.group == "special"
                && viewModel.specialsWaitForMilitary(mode: mode.rawValue)
                && !viewModel.allMilitaryComplete(mode: mode.rawValue, weaponId: weapon.weaponId)
                ? "mw4.ui.special_locked".localized()
                : camo.unlockLevel.map { viewModel.levelGateText($0, weaponId: weapon.weaponId, kind: "locked") },
            detail: militaryDetail(camo),
            onToggle: { viewModel.toggleCamo(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo) },
            onSetAmount: { viewModel.setCamoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo, amount: $0) }
        )
    }

    /// A Weapon Prestige camo, earned by the weapon's Prestige and level in
    /// every mode at once, so it's ticked the way a Military camo is.
    private func prestigeCamoRow(_ index: Int) -> some View {
        let camo = viewModel.prestigeCamos[index]
        let item = ChallengeItem(itemId: -1 - index,
                                 name: viewModel.prestigeCamoName(camo, weaponId: weapon.weaponId),
                                 imageURL: viewModel.prestigeCamoImageURL(camo, weaponId: weapon.weaponId),
                                 tier: nil, unlockLevel: nil, requirement: nil, children: [], group: "prestige")
        return ChallengeRow(
            item: item,
            accent: mode.accent,
            amount: 0,
            isDone: viewModel.isPrestigeCamoComplete(weaponId: weapon.weaponId, index: index),
            titleGradient: [Color].prestige(camo, index: index),
            detail: prestigeCamoDetail(camo),
            onToggle: { viewModel.togglePrestigeCamo(weaponId: weapon.weaponId, index: index) },
            onSetAmount: { _ in }
        )
    }

    /// "Prestige the HAN 86." or "Reach Prestige Master level 73."
    private func prestigeCamoDetail(_ camo: PrestigeCamo) -> String? {
        guard let stage = viewModel.prestigeCamoStage(camo) else { return nil }
        guard let level = viewModel.prestigeCamoLevel(camo, weaponId: weapon.weaponId) else {
            return String(format: "mw4.ui.prestige_camo.enter".localized(), weapon.name.resolved())
        }
        return String(format: "mw4.ui.prestige_camo.level".localized(),
                      viewModel.prestigeStages[stage - 1].name.resolved(), level)
    }

    /// "Earned at 17 weapon unlocks." or "Needs 17 weapon unlocks." under
    /// a Military camo, whose unlock count is all there is to it ("Earn 17
    /// weapon unlocks." in quick tick).
    private func militaryDetail(_ camo: ChallengeItem) -> String? {
        guard let level = viewModel.militaryLevel(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo) else { return nil }
        // Quick tick has no levels to unlock by: say what the game asks.
        guard !viewModel.quickTick else { return viewModel.levelGateText(level, weaponId: weapon.weaponId, kind: "reach") }
        let earned = viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo)
        return viewModel.levelGateText(level, weaponId: weapon.weaponId, kind: earned ? "earned" : "locked")
    }

    private static let rowInsets = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

    /// iPad: the weapon's art beside its name, level and Prestige in one
    /// wide card, then the camos and the Mastery trio as tiles, so the
    /// screen is filled rather than one phone-width column on a big canvas.
    /// A camo tile needs about 400pt to keep its sentence and its stepper on
    /// good terms, so an unfolded iPhone Duo held upright (about 670pt) gets
    /// the wide header over full-width tiles, and only wider screens a grid.
    private var tileColumns: Int { width >= 1250 ? 3 : (width >= 800 ? 2 : 1) }

    /// Columns for `count` tiles: 3 when they split into threes and there's
    /// room, else 2 (a tile left over stretches across its row).
    private func fitColumns(_ count: Int) -> Int {
        guard tileColumns > 1, count > 1 else { return 1 }
        if count % 3 == 0, width >= 1000 { return 3 }
        return 2
    }

    @ViewBuilder private var wideSections: some View {
        let columns = tileColumns
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                WeaponHeroImage(urlString: weapon.imageURL, height: 210)
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    if !viewModel.quickTick {
                        Divider().overlay(Color.appInkMuted.opacity(0.2))
                        CompactLevelRow(mode: mode, weapon: weapon)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Full width under the art, so the open list isn't squeezed
            // into the column beside it
            prestigeCamosBlock(columns: columns > 1 ? 2 : 1)
        }
        .padding(16)
        .borderedCard()
        .listRowInsets(Self.rowInsets)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        // The same tabs as on iPhone, one part at a time
        modeSwitchRow
        partPicker

        switch shownPart {
        case .camos:
            if camos.isEmpty {
                noCamoData
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(camoGroups, id: \.title) { group in
                    Section(group.title) {
                        tileRows(group.camos.map { camo in AnyView(camoRow(camo)) }, columns: fitColumns(group.camos.count))
                    }
                }
            }
        case .completionist:
            let steps = (0..<TrackerViewModel.completionistStepCount).map { step in
                AnyView(CompletionistStepRow(mode: mode, weapon: weapon, step: step))
            }
            let final = mode.hasFinalCamo ? [AnyView(FinalCamoRow(mode: mode, weapon: weapon))] : []
            tileRows(steps + final, columns: fitColumns(steps.count + final.count))
        case .mastery:
            tileRows((1...3).map { tier in AnyView(masteryRow(tier)) }, columns: fitColumns(3))
        }
    }

    /// A Mastery tier: this weapon's own challenge when the mode's Mastery
    /// is challenges, else the mode-wide count.
    @ViewBuilder private func masteryRow(_ tier: Int) -> some View {
        switch viewModel.masteryKind(mode: mode.rawValue, tier: tier) {
        case .challenge: MasteryChallengeRow(mode: mode, weapon: weapon, tier: tier)
        case .mode: MasteryModeChallengeRow(mode: mode, weapon: weapon, tier: tier)
        case .count: MasteryModeRow(mode: mode, tier: tier)
        }
    }

    /// Rows of `columns` tiles. A short last row stretches across rather
    /// than leaving a gap beside it.
    @ViewBuilder private func tileRows(_ tiles: [AnyView], columns: Int) -> some View {
        ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
            HStack(alignment: .top, spacing: 12) {
                ForEach(start..<min(start + columns, tiles.count), id: \.self) { index in
                    tiles[index].modifier(DetailTile())
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
            imageURL: camo.imageURL,
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
            guard let category = viewModel.category(containingWeaponId: weapon.weaponId) else { return "mw4.ui.locked".localized() }
            let progress = viewModel.completionistCategoryGateProgress(category, mode: mode.rawValue, step: step)
            let className = category.name.resolved()
            return before.map { String(format: "mw4.ui.completionist.locked_class".localized(), $0, progress.total, className, progress.done) }
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
        StatusRow(name: camo.name, achieved: achieved, color: camo.color, gradient: camo.gradient, detail: detail, imageURL: camo.imageURL)
    }
}

/// One of the mode's three Mastery camos: earned once enough weapons have
/// the final Completionist camo. Mode-wide, so it reads the same on every
/// weapon in the mode.
struct MasteryModeRow: View {
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
            detail: detail(progress),
            imageURL: camo.imageURL
        )
    }

    /// A mode-wide challenge reads as itself with its count (1/250); the
    /// older count rule as weapons with the last Completionist camo.
    private func detail(_ progress: (done: Int, total: Int)) -> String {
        if viewModel.masteryKind(mode: mode.rawValue, tier: tier) == .mode,
           let requirement = viewModel.modeMasteryRequirement(mode: mode.rawValue, tier: tier) {
            return "\(requirement.description.resolved()) \(progress.done)/\(progress.total)"
        }
        return String(format: "mw4.ui.mastery.weapons_needed".localized(), progress.done, progress.total, mode.lastCompletionist.name)
    }
}

/// A Mastery tier as one challenge for the whole mode (`mastery.unlock` is
/// "mode"). It reads the same on every weapon's page; ticking it on one
/// ticks it for the mode.
struct MasteryModeChallengeRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    let tier: Int
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camos: [MasteryCamo] {
        let tiers = mode.masteryCamos
        return [tiers.tier1, tiers.tier2, tiers.tier3]
    }
    private var camo: MasteryCamo { camos[tier - 1] }
    private var before: MasteryCamo { tier == 1 ? mode.lastCompletionist : camos[tier - 2] }
    private var requirement: Requirement? { viewModel.modeMasteryRequirement(mode: mode.rawValue, tier: tier) }

    private var item: ChallengeItem {
        ChallengeItem(itemId: -(20 + tier), name: LocalizedText(camo.name), imageURL: camo.imageURL,
                      tier: nil, unlockLevel: nil, requirement: requirement, children: [])
    }

    /// The tier before first, then the weapons it waits for.
    private var lockedReason: String {
        if tier > 1, !viewModel.isMasteryAchieved(mode: mode.rawValue, tier: tier - 1) {
            return String(format: "mw4.ui.mastery.mode_locked".localized(), before.name)
        }
        let needed = viewModel.modeMasteryWeaponsNeeded(mode: mode.rawValue, tier: tier)
        if needed <= 1 {
            return String(format: "mw4.ui.mastery.mode_locked_first".localized(), mode.lastCompletionist.name)
        }
        return String(format: "mw4.ui.mastery.weapons_needed".localized(),
                      min(viewModel.lastCompletionistCount(mode: mode.rawValue), needed), needed, mode.lastCompletionist.name)
    }

    var body: some View {
        if viewModel.modeMasteryCountsItself(mode: mode.rawValue, tier: tier) {
            let progress = viewModel.masteryProgress(mode: mode.rawValue, tier: tier)
            StatusRow(
                name: camo.name,
                achieved: viewModel.isMasteryAchieved(mode: mode.rawValue, tier: tier),
                color: camo.color,
                gradient: camo.gradient,
                detail: viewModel.isModeMasteryAvailable(mode: mode.rawValue, tier: tier)
                    ? String(format: "mw4.ui.mastery.self_count".localized(), progress.done, progress.total,
                             (viewModel.modeMasteryCountedCamo(mode: mode.rawValue, tier: tier) ?? mode.completionist.steps[2]).name)
                    : lockedReason,
                imageURL: camo.imageURL
            )
        } else {
            ChallengeRow(
                item: item,
                accent: camo.color,
                amount: viewModel.modeMasteryAmount(mode: mode.rawValue, tier: tier),
                isDone: viewModel.isModeMasteryComplete(mode: mode.rawValue, tier: tier),
                isAvailable: viewModel.isModeMasteryAvailable(mode: mode.rawValue, tier: tier),
                lockedReason: lockedReason,
                titleGradient: camo.gradient,
                onToggle: { viewModel.toggleModeMastery(mode: mode.rawValue, tier: tier, weaponId: weapon.weaponId) },
                onSetAmount: { viewModel.setModeMasteryAmount(mode: mode.rawValue, tier: tier, weaponId: weapon.weaponId, amount: $0) }
            )
        }
    }
}

/// A Mastery tier as this weapon's own challenge (`mastery.unlock` is
/// "challenge"), ticked and counted like Platinum.
private struct MasteryChallengeRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    let tier: Int
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camos: [MasteryCamo] {
        let tiers = mode.masteryCamos
        return [tiers.tier1, tiers.tier2, tiers.tier3]
    }
    private var camo: MasteryCamo { camos[tier - 1] }
    /// What this tier builds on: the last Completionist camo, or the tier before.
    private var before: MasteryCamo { tier == 1 ? mode.lastCompletionist : camos[tier - 2] }

    private var item: ChallengeItem {
        ChallengeItem(itemId: -(10 + tier), name: LocalizedText(camo.name), imageURL: camo.imageURL,
                      tier: nil, unlockLevel: nil,
                      requirement: viewModel.masteryRequirement(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier),
                      children: [])
    }

    private var lockedReason: String {
        let ownDone = tier == 1
            ? viewModel.hasLastCompletionist(mode: mode.rawValue, weaponId: weapon.weaponId)
            : viewModel.hasTierBefore(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier)
        guard ownDone else {
            let forTheMode = tier > 1 && viewModel.masteryKind(mode: mode.rawValue, tier: tier - 1) != .challenge
            return String(format: (forTheMode ? "mw4.ui.mastery.mode_locked" : "mw4.ui.completionist.locked_previous").localized(), before.name)
        }
        switch viewModel.masteryGate(mode: mode.rawValue, tier: tier) {
        case .weapon:
            return "mw4.ui.locked".localized()
        case .category:
            guard let category = viewModel.category(containingWeaponId: weapon.weaponId) else { return "mw4.ui.locked".localized() }
            let progress = viewModel.masteryGateProgress(mode: mode.rawValue, tier: tier, category: category)
            return String(format: "mw4.ui.completionist.locked_class".localized(), before.name, progress.total, category.name.resolved(), progress.done)
        case .mode:
            let progress = viewModel.masteryGateProgress(mode: mode.rawValue, tier: tier)
            return String(format: "mw4.ui.completionist.locked_mode".localized(), before.name, progress.total, progress.done)
        }
    }

    var body: some View {
        ChallengeRow(
            item: item,
            accent: camo.color,
            amount: viewModel.weaponMasteryAmount(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier),
            isDone: viewModel.isWeaponMasteryComplete(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier),
            isAvailable: viewModel.isWeaponMasteryAvailable(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier),
            lockedReason: lockedReason,
            titleGradient: camo.gradient,
            onToggle: { viewModel.toggleWeaponMastery(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier) },
            onSetAmount: { viewModel.setWeaponMasteryAmount(mode: mode.rawValue, weaponId: weapon.weaponId, tier: tier, amount: $0) }
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
    var imageURL: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: achieved ? 21 : 17))
                .foregroundStyle(achieved ? color : Color.appInkMuted.opacity(0.5))
                .frame(width: 21, height: 21)

            // Same picture slot as the camo list's rows.
            if imageURL != nil {
                CamoThumbnail(urlString: imageURL, size: 34)
                    .opacity(achieved ? 1 : 0.4)
            }

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
        .preference(key: EarnedGradientKey.self, value: achieved ? gradient : nil)
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
    /// Before any Weapon Prestige the game counts unlocks; a prestiged
    /// weapon goes back to classic levels.
    private var countsUnlocks: Bool { viewModel.countsUnlocks(weaponId: weapon.weaponId) }
    /// The number the stepper shows and steps: unlocks, or the prestige
    /// stage's level.
    private var shown: Int { countsUnlocks ? TrackerViewModel.unlocks(forLevel: level) : level }
    private var shownMax: Int { countsUnlocks ? TrackerViewModel.unlocks(forLevel: maxLevel) : maxLevel }
    private func setShown(_ value: Int) {
        viewModel.setLevel(countsUnlocks ? TrackerViewModel.level(forUnlocks: value) : value, for: weapon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            levelLine
            if countsUnlocks {
                // Why the game's weapon level can be well ahead of this
                Text("mw4.ui.unlocks_hint".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stageCount > 0 {
                prestigeLine
            }
        }
        .alert((countsUnlocks ? "mw4.ui.set_unlocks.title" : "mw4.ui.set_level.title").localized(), isPresented: $showValueEntry) {
            TextField("mw4.ui.set_amount.field".localized(), text: $valueText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.save".localized()) {
                if let entered = Int(valueText) {
                    viewModel.setLevel(countsUnlocks ? TrackerViewModel.level(forUnlocks: entered) : entered, for: weapon)
                }
            }
        } message: {
            Text(String(format: "mw4.ui.set_level.message".localized(), 0, countsUnlocks ? TrackerViewModel.unlocks(forLevel: maxLevel) : maxLevel))
        }
    }

    /// Stage pips and the current stage's name on the left; on the right one
    /// button named after the stage it moves to, so it reads as "go to
    /// Prestige 1" rather than a bare +. It only lights up once the current
    /// stage is maxed. The small undo beside it steps back a mistaken tap.
    /// With a single stage (MW4's Prestige Master) there's nothing to count:
    /// no pips and no "None yet", just a Prestige button, then the stage's
    /// name once the weapon is in it.
    private var prestigeLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("mw4.ui.prestige".localized())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appInkMuted)
                    if stageCount == 1 {
                        if prestige > 0, let name = viewModel.prestigeName(for: weapon.weaponId) {
                            Text(name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(mode.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else {
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
                            Text(stageCount == 1 ? "mw4.ui.prestige".localized() : viewModel.prestigeStages[prestige].name.resolved())
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
                Text(countsUnlocks ? String(format: "mw4.ui.prestige.hint_unlocks".localized(), shownMax)
                                   : String(format: "mw4.ui.prestige.hint".localized(), maxLevel))
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
                // Full size whenever it fits. A bare minimumScaleFactor shrank
                // it with room to spare (sized before the row had its width).
                let label = Text(prestige > 0 ? (viewModel.prestigeName(for: weapon.weaponId) ?? "mw4.ui.weapon_level".localized())
                                              : (countsUnlocks ? "mw4.ui.weapon_unlocks" : "mw4.ui.weapon_level").localized())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    label.fixedSize()
                    label.minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                stepButton(systemName: "minus", enabled: shown > 0, size: 26, accent: mode.accent) {
                    setShown(shown - 1)
                }

                Button {
                    valueText = "\(shown)"
                    showValueEntry = true
                } label: {
                    Text("\(shown)/\(shownMax)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(mode.accent)
                        .contentTransition(.numericText())
                        .frame(minWidth: 56)
                }
                .buttonStyle(.plain)

                stepButton(systemName: "plus", enabled: shown < shownMax, size: 26, accent: mode.accent) {
                    setShown(shown + 1)
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
    @AppStorage(CardOutline.key) private var outline = CardOutline.prestige.rawValue

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appSurface))
            // An earned Completionist or Mastery camo outlines its tile in
            // its own colors, like the weapon cards.
            .overlayPreferenceValue(EarnedGradientKey.self) { colors in
                if let colors, colors.count > 1, outline != CardOutline.off.rawValue {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.7), lineWidth: 1)
                }
            }
            .transformPreference(EarnedGradientKey.self) { $0 = nil }
    }
}
