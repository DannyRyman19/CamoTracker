import PhotosUI
import SwiftUI
import Vision

/// Reads stash counts out of photos or screenshots of the 3D Printer's
/// recipe screens, where each ingredient shows as its name with "have/need"
/// under it ("Synthetics" then "607/50"). Runs on the device with Vision.
enum HajinStashScanner {
    struct Line {
        let text: String
        let box: CGRect   // Vision's normalised box, origin bottom left
    }

    static func lines(in image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { obs in
            obs.topCandidates(1).first.map { Line(text: $0.string, box: obs.boundingBox) }
        }
    }

    /// Ingredient and resource counts found in the lines: a name the guide
    /// knows, then the first number of the "have/need" just below it (or on
    /// the same line).
    static func counts(in lines: [Line], items: [HajinGuide.Item]) -> [String: Int] {
        let names = items.map { (id: $0.id, key: normalised($0.name.resolved)) }.filter { $0.key.count >= 3 }
        // The stash screen lists resources as a name over a plain total
        let resources = Set(items.filter { $0.kind == "Resource" }.map(\.id))
        func amount(_ text: String, for id: String) -> Int? {
            have(in: text) ?? (resources.contains(id) ? plain(text) : nil)
        }
        var found: [String: Int] = [:]
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        for (i, line) in sorted.enumerated() {
            guard let id = match(line.text, names) else { continue }
            if let n = have(in: line.text) {
                found[id] = n
                continue
            }
            if resources.contains(id), let n = plain(line.text.replacingOccurrences(of: #"^\D+"#, with: "", options: .regularExpression)) {
                found[id] = n
                continue
            }
            // The count sits just under the name, roughly left-aligned with it
            let below = sorted[(i + 1)...].prefix(4).first { other in
                let gap = line.box.minY - other.box.maxY
                // Same text size, so a big screen title never takes a count
                let scale = other.box.height / max(line.box.height, 0.0001)
                return gap > -line.box.height * 0.5 && gap < line.box.height * 2.5
                    && scale > 0.6 && scale < 1.6
                    && abs(other.box.minX - line.box.minX) < max(line.box.width, 0.08)
                    && amount(other.text, for: id) != nil
            }
            if let below, let n = amount(below.text, for: id) { found[id] = n }
        }
        return found
    }

    /// The bank balance from the stash screen's "BANK $33,050 / $1M": the
    /// first number after BANK, on the same line (it can be split into
    /// several pieces of text). Nil when there's no BANK.
    static func bank(in lines: [Line]) -> Int? {
        guard let label = lines.first(where: { $0.text.uppercased().contains("BANK") }) else { return nil }
        let sameLine = lines.filter { abs($0.box.midY - label.box.midY) < label.box.height * 0.8 && $0.box.minX >= label.box.minX - 0.01 }
            .sorted { $0.box.minX < $1.box.minX }
        var text = sameLine.map(\.text).joined(separator: " ")
        if let r = text.uppercased().range(of: "BANK") { text = String(text[r.upperBound...]) }
        // "33,050 / 1M": digits and separators up to the slash
        let beforeSlash = text.split(separator: "/").first.map(String.init) ?? text
        guard let m = beforeSlash.firstMatch(of: /\d[\d,\.\s]*/) else { return nil }
        let digits = String(m.0).filter(\.isNumber)
        guard digits.count >= 1, digits.count <= 9 else { return nil }
        return Int(digits)
    }

    /// The DMZ level from the stash screen's side panel: "LVL 38", or "LVL"
    /// with the number just under it. (The big number above it is the
    /// player's frames, not the level.)
    static func level(in lines: [Line]) -> Int? {
        let levels = 1...70   // HajinStore.maxLevel (main-actor, so not usable here)
        for label in lines where label.text.uppercased().contains("LVL") {
            let after = label.text.uppercased().components(separatedBy: "LVL").last ?? ""
            if let n = Int(after.filter(\.isNumber)), levels.contains(n) { return n }
            // the number on the next line down, roughly in line with LVL
            let below = lines.filter { other in
                let gap = label.box.minY - other.box.maxY
                return gap > -label.box.height && gap < label.box.height * 2.5 && abs(other.box.minX - label.box.minX) < 0.05
            }
            for other in below {
                if let n = plain(other.text), levels.contains(n) { return n }
            }
        }
        return nil
    }

    /// "607/50", "607 / 50" or "Synthetics 607/50" gives 607.
    static func have(in text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "O", with: "0")
        guard let m = cleaned.firstMatch(of: /(\d{1,5})\s*\/\s*\d{1,5}/), let n = Int(m.1) else { return nil }
        return n
    }

    /// A line that is only a number: "793" or "1,240".
    static func plain(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 6, t.allSatisfy(\.isNumber) else { return nil }
        return Int(t)
    }

    private static func normalised(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter }
    }

    /// The guide item the text names: exact once letters are compared, or
    /// off by a letter or two for longer names (OCR slips).
    private static func match(_ text: String, _ names: [(id: String, key: String)]) -> String? {
        let letters = text.replacingOccurrences(of: #"\d.*$"#, with: "", options: .regularExpression)
        let key = normalised(letters)
        guard key.count >= 3 else { return nil }
        if let exact = names.first(where: { $0.key == key }) { return exact.id }
        // A photo that cuts off the left edge: "thetics" is Synthetics, when
        // only one name ends that way
        if key.count >= 5 {
            let tails = names.filter { $0.key.hasSuffix(key) }
            if tails.count == 1 { return tails[0].id }
        }
        let best = names.map { ($0.id, distance(key, $0.key), $0.key.count) }.min { $0.1 < $1.1 }
        guard let best, best.1 <= max(1, best.2 / 8) else { return nil }
        return best.0
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] : 1 + min(prev[j - 1], prev[j], cur[j - 1])
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

/// "Read counts from photos": pick photos, read them, review what changes.
struct HajinStashScanButton: View {
    @EnvironmentObject private var store: HajinStore
    @State private var picks: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var result: [String: Int]?
    @State private var resultCash: Int?
    @State private var resultLevel: Int?

    var body: some View {
        PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
            HStack(spacing: 10) {
                Image(systemName: reading ? "hourglass" : "text.viewfinder")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentDMZ)
                VStack(alignment: .leading, spacing: 2) {
                    Text((reading ? "mw4.ui.hajin.scan_reading" : "mw4.ui.hajin.scan").localized())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appInk)
                    Text("mw4.ui.hajin.scan_hint".localized())
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.appSurface))
        }
        .buttonStyle(.plain)
        .disabled(reading)
        .onChange(of: picks) { chosen in
            guard !chosen.isEmpty else { return }
            read(chosen)
        }
        .sheet(isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            if let result { HajinStashScanReview(found: result, cash: resultCash, level: resultLevel) }
        }
    }

    private func read(_ chosen: [PhotosPickerItem]) {
        reading = true
        let items = (store.guide?.items ?? []).filter(HajinStore.inStash)
        Task {
            var seen: [String: [Int]] = [:]
            var bank: Int?
            var lvl: Int?
            for pick in chosen {
                guard let data = try? await pick.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.cgImage else { continue }
                let (counts, cash, level) = await Task.detached(priority: .userInitiated) { () -> ([String: Int], Int?, Int?) in
                    let lines = HajinStashScanner.lines(in: image)
                    return (HajinStashScanner.counts(in: lines, items: items), HajinStashScanner.bank(in: lines), HajinStashScanner.level(in: lines))
                }.value
                for (id, n) in counts { seen[id, default: []].append(n) }
                if let cash { bank = cash }
                if let level { lvl = level }
            }
            // The same ingredient on several screens: take the count read most
            // often, the higher one on a tie
            let merged = seen.mapValues { values in
                Dictionary(grouping: values, by: { $0 }).max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }!.key
            }
            await MainActor.run {
                reading = false
                picks = []
                resultCash = bank
                resultLevel = lvl
                result = merged
            }
        }
    }
}

/// What the photos said against what the stash has; tick off anything
/// misread, then update the stash in one go.
struct HajinStashScanReview: View {
    let found: [String: Int]
    /// Items the reader wasn't sure of: shown with a "check" tag.
    var unsure: Set<String> = []
    /// The bank balance read from the photo, if it showed one.
    var cash: Int? = nil
    /// The DMZ level read from the photo, if it showed one.
    var level: Int? = nil
    /// Stash photos: how sure the icon model was of each item (its least
    /// certain stack) and how many stacks it found.
    var sureness: [String: Float] = [:]
    var stacks: [String: Int] = [:]
    /// Stash photos: the photo and the reader's working, for "Send this photo"
    var report: HajinScanReport? = nil
    /// Called after Update or Cancel, e.g. to close the framing screen too.
    var onDone: (() -> Void)? = nil
    /// How many photos these counts come from (stash photos added together).
    var photos = 1
    /// Stash photos: read another photo (the Valuables tab after the
    /// Ingredients tab, say) and add it to these counts, as edited.
    var onAddPhoto: (([String: Int]) -> Void)? = nil
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var skip: Set<String> = []
    @State private var edited: [String: Int] = [:]
    @State private var editing: HajinGuide.Item?
    @State private var editText = ""
    @State private var skipCash = false
    @State private var skipLevel = false
    @State private var detent = PresentationDetent.medium
    /// After Update: offer to send the photo and corrections, unless the
    /// player has said not to ask again
    @AppStorage("mw4_hajin_ask_send_scan") private var askToSend = true
    @State private var asking = false
    @State private var sentState: (had: [String: Int], edited: [String: Int], skipped: Set<String>)?
    @State private var mail: HajinMailDraft?
    @State private var share: [Any]?

    private var rows: [(item: HajinGuide.Item, now: Int, read: Int)] {
        // Only what My stash tracks: resources, ingredients and valuables.
        // The photo reader also recognises keys and gear, and leaves them out.
        found.compactMap { id, n in store.guide?.item(id).flatMap { HajinStore.inStash($0) ? $0 : nil }
            .map { ($0, store.count(of: id), edited[id] ?? n) } }
            // Ones to check first, then anything under 100% sure (least sure
            // first), then changes, then ones already right
            .sorted { (rank($0), percent($0), $0.item.name.resolved) < (rank($1), percent($1), $1.item.name.resolved) }
    }

    private func rank(_ row: (item: HajinGuide.Item, now: Int, read: Int)) -> Int {
        if unsure.contains(row.item.id) && edited[row.item.id] == nil { return 0 }
        if percent(row) < 100 { return 1 }
        return row.now == row.read ? 3 : 2
    }

    /// How sure the reader was, as shown on the row; 100 for edited rows and
    /// ones read from text (resources), which carry no figure
    private func percent(_ row: (item: HajinGuide.Item, now: Int, read: Int)) -> Int {
        guard edited[row.item.id] == nil, let sure = sureness[row.item.id] else { return 100 }
        return Int((sure * 100).rounded())
    }

    /// "10 · Already right": the value, then the note.
    private func sameLabel(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInk)
            Text("mw4.ui.hajin.scan_same".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(HajinStore.printableGreen)
        }
    }

    /// A single value read from the photo (level), now → read, tap to skip.
    private func valueRow(symbol: String, title: String, now: String, read: String, same: Bool, skipped: Binding<Bool>) -> some View {
        Button { if !same { skipped.wrappedValue.toggle() } } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentDMZ).frame(width: 32)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                Spacer(minLength: 8)
                if same {
                    sameLabel(read)
                } else {
                    Text("\(now) → \(read)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(skipped.wrappedValue ? Color.appInkMuted : Color.appInk)
                        .strikethrough(skipped.wrappedValue)
                    Image(systemName: skipped.wrappedValue ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(skipped.wrappedValue ? Color.appInkMuted : Color.accentDMZ)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func itemRow(_ row: (item: HajinGuide.Item, now: Int, read: Int)) -> some View {
        let same = row.now == row.read
        let on = !same && !skip.contains(row.item.id)
        Button {
            guard !same else { return }
            if skip.contains(row.item.id) { skip.remove(row.item.id) } else { skip.insert(row.item.id) }
        } label: {
            HStack(spacing: 12) {
                HajinItemTile(item: row.item, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                    HStack(spacing: 6) {
                        if unsure.contains(row.item.id) && edited[row.item.id] == nil {
                            Text("mw4.ui.hajin.scan_check".localized().uppercased())
                                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                                .foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.24))
                        }
                        if let sure = sureness[row.item.id] {
                            Text(String(format: "mw4.ui.hajin.scan_sure".localized(), stacks[row.item.id] ?? 1, Int((sure * 100).rounded())))
                                .font(.caption2)
                                .foregroundStyle(sure < 0.5 ? Color(red: 0.96, green: 0.66, blue: 0.24) : Color.appInkMuted)
                        }
                    }
                }
                Spacer(minLength: 8)
                if same {
                    sameLabel("\(row.read)")
                } else {
                    Text("\(row.now) → \(row.read)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(on ? Color.appInk : Color.appInkMuted)
                        .strikethrough(!on)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Color.accentDMZ : Color.appInkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("mw4.ui.hajin.scan_edit".localized()) { editText = "\(row.read)"; editing = row.item }
        }
        .swipeActions {
            Button("mw4.ui.hajin.scan_edit".localized()) { editText = "\(row.read)"; editing = row.item }.tint(.accentDMZ)
        }

    }

    var body: some View {
        let all = rows
        let changes = all.filter { $0.now != $0.read && !skip.contains($0.item.id) }
        let cashChange = cash.flatMap { $0 != store.cash && !skipCash ? $0 : nil }
        let levelChange = level.flatMap { $0 != store.dmzLevel && !skipLevel ? $0 : nil }
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if all.isEmpty && cash == nil && level == nil {
                    Text("mw4.ui.hajin.scan_none".localized())
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                } else {
                    // How to edit, before the rows it's about
                    Label("mw4.ui.hajin.scan_edit_hint".localized(), systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
                // Sending the photo comes first, so it's seen without scrolling
                if let report {
                    Section {
                        HajinSendScanButton(report: report) {
                            (Dictionary(uniqueKeysWithValues: all.map { ($0.item.id, $0.now) }), edited, skip)
                        }
                    } footer: {
                        Text("mw4.ui.hajin.send_scan_footer".localized())
                    }
                }
                // Level, cash, resources and ingredients each in their own section
                if let level {
                    Section("mw4.ui.hajin.dmz_level".localized()) {
                        valueRow(symbol: "chart.bar.fill", title: "mw4.ui.hajin.dmz_level".localized(),
                                 now: store.dmzLevel > 0 ? "\(store.dmzLevel)" : "–", read: "\(level)",
                                 same: level == store.dmzLevel, skipped: $skipLevel)
                    }
                }
                if let cash {
                    Section("mw4.ui.hajin.cash_title".localized()) {
                        let same = cash == store.cash
                        Button { if !same { skipCash.toggle() } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "banknote.fill").font(.title3).foregroundStyle(Color.accentDMZ).frame(width: 32)
                                Text("mw4.ui.hajin.cash_title".localized()).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                                Spacer(minLength: 8)
                                if same {
                                    sameLabel("$\(cash.formatted())")
                                } else {
                                    Text("$\(store.cash.formatted()) → $\(cash.formatted())")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(skipCash ? Color.appInkMuted : Color.appInk)
                                        .strikethrough(skipCash)
                                    Image(systemName: skipCash ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(skipCash ? Color.appInkMuted : Color.accentDMZ)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                let resources = all.filter { $0.item.kind == "Resource" }
                let ingredients = all.filter { $0.item.kind == "Ingredient" }
                let valuables = all.filter { $0.item.kind == "Valuable" }
                if !resources.isEmpty {
                    Section("mw4.ui.hajin.resources".localized()) {
                        ForEach(resources, id: \.item.id) { row in itemRow(row) }
                    }
                }
                if !ingredients.isEmpty {
                    Section("mw4.ui.hajin.ingredients".localized()) {
                        ForEach(ingredients, id: \.item.id) { row in itemRow(row) }
                    }
                }
                if !valuables.isEmpty {
                    Section("mw4.ui.hajin.valuables".localized()) {
                        ForEach(valuables, id: \.item.id) { row in itemRow(row) }
                    }
                }
                if let onAddPhoto {
                    Section {
                        Button {
                            Haptics.step()
                            // What's been read so far, as edited, less anything skipped
                            var carried = found.merging(edited) { _, new in new }
                            for id in skip { carried[id] = nil }
                            onAddPhoto(carried)
                            dismiss()
                        } label: {
                            Label("mw4.ui.hajin.scan_add_photo".localized(), systemImage: "plus.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentDMZ)
                        }
                    } footer: {
                        Text(photos > 1 ? String(format: "mw4.ui.hajin.scan_photos".localized(), photos)
                                        : "mw4.ui.hajin.scan_add_photo_footer".localized())
                    }
                }
            }
            #if DEBUG
            .task { await demo(proxy) }
            #endif
            .alert(editing?.name.resolved ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("0", text: $editText).keyboardType(.numberPad)
                Button("mw4.ui.hajin.save".localized()) {
                    if let item = editing, let n = Int(editText) { edited[item.id] = n; skip.remove(item.id) }
                    editing = nil
                }
                Button("mw4.ui.hajin.cancel".localized(), role: .cancel) { editing = nil }
            }
            .alert("mw4.ui.hajin.send_ask_title".localized(), isPresented: $asking) {
                Button("mw4.ui.hajin.send_ask_send".localized()) { sendReport() }
                Button("mw4.ui.hajin.send_ask_never".localized()) { askToSend = false; finish() }
                Button("mw4.ui.hajin.send_ask_later".localized(), role: .cancel) { finish() }
            } message: {
                Text("mw4.ui.hajin.send_ask_message".localized())
            }
            .sheet(item: $mail, onDismiss: finish) { draft in HajinMailView(draft: draft).ignoresSafeArea() }
            .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } }), onDismiss: finish) {
                if let share { HajinShareSheet(items: share) }
            }
            .navigationTitle("mw4.ui.hajin.scan_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { dismiss(); onDone?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.scan_apply".localized()) { apply(changes, cash: cashChange, level: levelChange) }
                        .disabled(changes.isEmpty && cashChange == nil && levelChange == nil)
                }
            }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    #if DEBUG
    /// SS_GRID_DEMO: open the sheet up, scroll down the rows, then update
    /// and open My stash, for the screen recording.
    private func demo(_ proxy: ScrollViewProxy) async {
        guard ProcessInfo.processInfo.environment["SS_GRID_DEMO"] != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { detent = .large }
        try? await Task.sleep(for: .seconds(1.5))
        let all = rows
        let order = all.filter { $0.item.kind == "Resource" } + all.filter { $0.item.kind == "Ingredient" } + all.filter { $0.item.kind == "Valuable" }
        for row in order.dropFirst(3) {
            withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(row.item.id, anchor: .bottom) }
            try? await Task.sleep(for: .seconds(0.45))
        }
        try? await Task.sleep(for: .seconds(1.5))
        apply(all.filter { $0.now != $0.read && !skip.contains($0.item.id) },
              cash: cash.flatMap { $0 != store.cash ? $0 : nil }, level: level.flatMap { $0 != store.dmzLevel ? $0 : nil }, ask: false)
        try? await Task.sleep(for: .seconds(2.5))
        NotificationCenter.default.post(name: .hajinDemoOpenStash, object: nil)
    }
    #endif

    private func apply(_ changes: [(item: HajinGuide.Item, now: Int, read: Int)], cash cashChange: Int?, level levelChange: Int?, ask: Bool = true) {
        Haptics.step()
        // What the stash had before this update, for the report
        let had = Dictionary(uniqueKeysWithValues: rows.map { ($0.item.id, $0.now) })
        store.applyScannedCounts(Dictionary(uniqueKeysWithValues: changes.map { ($0.item.id, $0.read) }))
        if let cashChange { store.setCash(cashChange) }
        if let levelChange { store.setLevel(levelChange) }
        // Stash photos: with everything applied, offer to send the photo
        if ask, askToSend, report != nil {
            sentState = (had, edited, skip)
            asking = true
        } else {
            finish()
        }
    }

    private func sendReport() {
        guard let report, let state = sentState else { finish(); return }
        switch report.outgoing(had: state.had, edited: state.edited, skipped: state.skipped) {
        case .mail(let draft): mail = draft
        case .share(let items): share = items
        case nil: finish()
        }
    }

    private func finish() {
        dismiss()
        onDone?()
    }
}

extension Notification.Name {
    /// SS_GRID_DEMO: the review has updated; open My stash
    static let hajinDemoOpenStash = Notification.Name("hajinDemoOpenStash")
}
