import SwiftUI
import Vision

/// After a match: a photo of the backpack (the exfil summary, or the
/// backpack screen) read like a stash photo, but 4 tiles wide, with the
/// Secure slots under it and the resources in the SORT panel beside it.
/// The review says what to sell, the player marks each Sold or Keep, and
/// whatever's kept goes into My stash.
enum HajinBackpack {
    static let columns = 4

    /// Vision reads some of the game's capitals as Cyrillic look-alikes
    /// ("ВАСКРАСК"): back to Latin, upper case, no spaces.
    static func normalised(_ text: String) -> String {
        let map: [Character: Character] = ["А": "A", "В": "B", "С": "C", "Е": "E", "К": "K", "М": "M", "Н": "H",
                                           "О": "O", "Р": "P", "Т": "T", "Х": "X", "У": "Y"]
        return String(text.uppercased().compactMap { $0 == " " ? nil : (map[$0] ?? $0) })
    }

    /// The text around the grid, in fractions with the origin at the top left.
    struct Landmarks {
        /// "MEDIUM BACKPACK" over the grid: its left edge and foot are the grid's top left
        var header: CGRect?
        /// "SECURE SLOTS" under the grid, over the secure row
        var secure: CGRect?
        /// "SORT" over the resource panel to the grid's right
        var sort: CGRect?
    }

    static func landmarks(_ lines: [HajinStashScanner.Line]) -> Landmarks {
        func box(_ l: HajinStashScanner.Line) -> CGRect {
            CGRect(x: l.box.minX, y: 1 - l.box.maxY, width: l.box.width, height: l.box.height)
        }
        var out = Landmarks()
        // The longest line saying BACKPACK: the item menu's lone "BACKPACK" isn't it
        out.header = lines.filter { normalised($0.text).contains("BACKPACK") && normalised($0.text).count > 8 }
            .max { $0.text.count < $1.text.count }.map(box)
        out.secure = lines.first { normalised($0.text).contains("SECURESLOT") }.map(box)
        out.sort = lines.first { normalised($0.text) == "SORT" }.map(box)
        return out
    }

    /// The grid's corners (TL, TR, BR, BL, fractions) from the text round
    /// it: the header pins the top left, SORT the right (its panel sits a
    /// third of a tile off the grid), SECURE SLOTS the bottom.
    static func guess(_ lines: [HajinStashScanner.Line], size: CGSize) -> [CGPoint]? {
        let marks = landmarks(lines)
        guard let header = marks.header, let sort = marks.sort else { return nil }
        let W = size.width, H = size.height
        let left = header.minX * W, top = header.maxY * H
        let sortX = sort.minX * W
        guard sortX > left else { return nil }
        let right = left + (sortX - left) / (1 + 0.3 / CGFloat(columns))
        let pitch = (right - left) / CGFloat(columns)
        var bottom = top + pitch * 4, bottomLeft = left
        if let secure = marks.secure, secure.minY * H > top + pitch {
            bottom = secure.minY * H - pitch * 0.1
            bottomLeft = secure.minX * W - pitch * 0.1
        }
        let shift = bottomLeft - left
        let corners = [CGPoint(x: left, y: top + pitch * 0.04), CGPoint(x: right, y: top + pitch * 0.04),
                       CGPoint(x: right + shift, y: bottom), CGPoint(x: bottomLeft, y: bottom)]
        HajinGridDebug.log("backpack: header \(header) sort \(sort) secure \(marks.secure.map { "\($0)" } ?? "-") -> \(corners.map { "(\(Int($0.x)),\(Int($0.y)))" })")
        return corners.map { CGPoint(x: min(max($0.x / W, 0), 1), y: min(max($0.y / H, 0), 1)) }
    }

    /// Rows in the framed backpack, from its shape: small to large packs
    /// are 3 to 5 rows of square tiles.
    static func rows(for corners: [CGPoint], size: CGSize) -> Int {
        min(max(HajinStashGrid.rows(for: corners, size: size, columns: columns), 2), 6)
    }

    /// The secure row under the grid: as wide as it, a tile tall, starting
    /// just under SECURE SLOTS (or where that usually is).
    static func secureRow(_ corners: [CGPoint], lines: [HajinStashScanner.Line], size: CGSize) -> [CGPoint] {
        let W = size.width, H = size.height
        let p = corners.map { CGPoint(x: $0.x * W, y: $0.y * H) }
        let pitch = hypot(p[1].x - p[0].x, p[1].y - p[0].y) / CGFloat(columns)
        let side = CGPoint(x: p[3].x - p[0].x, y: p[3].y - p[0].y)
        let length = max(hypot(side.x, side.y), 1)
        let down = CGPoint(x: side.x / length, y: side.y / length)
        // How far below the grid the row starts: from the label when it's
        // read and sensible, else the usual gap
        var gap = pitch * 0.39
        if let secure = landmarks(lines).secure {
            let g = (secure.maxY * H - p[3].y) / max(down.y, 0.1) + pitch * 0.05
            if g > 0, g < pitch * 1.2 { gap = g }
        }
        func along(_ point: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: (point.x + down.x * d) / W, y: (point.y + down.y * d) / H) }
        return [along(p[3], gap), along(p[2], gap), along(p[2], gap + pitch), along(p[3], gap + pitch)]
    }

    /// The SORT panel's four totals, top to bottom: synthetics, electronics,
    /// chemicals, metals (its icons: a sheet, a chip, a flask, a nut).
    static func resources(_ lines: [HajinStashScanner.Line]) -> [String: Int] {
        guard let sort = landmarks(lines).sort else { return [:] }
        func box(_ l: HajinStashScanner.Line) -> CGRect { CGRect(x: l.box.minX, y: 1 - l.box.maxY, width: l.box.width, height: l.box.height) }
        // The panel under SORT: about its width, a dozen lines deep
        let panel = CGRect(x: sort.minX - sort.width * 0.5, y: sort.maxY,
                           width: sort.width * 2.5, height: sort.height * 14)
        let below: [(HajinStashScanner.Line, CGRect)] = lines.map { ($0, box($0)) }
            .filter { panel.intersects($0.1) && $0.1.minY > sort.minY }
            .sorted { $0.1.minY < $1.1.minY }
        var cap = 999
        var values: [Int] = []
        for (line, _) in below {
            let text = normalised(line.text)
            if text.hasPrefix("MAX") {
                if let n = Int(text.filter(\.isNumber)) { cap = n }
                break
            }
            guard values.count < 4, let range = text.range(of: #"[0-9O]{3}$"#, options: .regularExpression) else { continue }
            values.append(Int(text[range].replacingOccurrences(of: "O", with: "0")) ?? 0)
        }
        guard values.count == 4 else { return [:] }
        // A misread first digit (043 as 843) can't be over the backpack's cap
        let fixed = values.map { $0 > cap ? $0 % 100 : $0 }
        return Dictionary(uniqueKeysWithValues: zip(["synthetics", "electronics", "chemicals", "metals"], fixed).filter { $0.1 > 0 })
    }

    /// What one photo read: the backpack and secure slots, as guide items
    /// and counts, the blueprints picked up, and the resources.
    @available(iOS 17.0, *)
    static func read(_ image: CGImage, corners: [CGPoint], lines: [HajinStashScanner.Line], known guide: HajinGuide?) -> HajinPostMatchResult {
        let size = CGSize(width: image.width, height: image.height)
        let blueprints = Set((guide?.items ?? []).filter { $0.blueprint == true }.map(\.id))
        let gridRows = rows(for: corners, size: size)
        let secureCorners = secureRow(corners, lines: lines, size: size)
        // Each tile with where it is on the photo, for the review to light up
        var tiles = HajinStashGrid.read(image, corners: corners, rows: gridRows, columns: columns, blueprints: blueprints)
            .map { ($0, $0.place ?? quad(corners, row: $0.row, column: $0.column, rows: gridRows)) }
        // The secure row, read where it is rather than fitted to lines: the
        // SECURE SLOTS label's box looks like another row
        let secure = HajinStashGrid.read(image, corners: secureCorners, rows: 1, columns: columns,
                                         blueprints: blueprints, fitBorders: false)
        // A free secure slot shows a grey shield, which a weak read takes
        // for a Riot Shield
        tiles += secure.filter { !($0.id == "riot-shield" && $0.confidence < 0.7) }
            // Read after the grid: its row sits under the last one
            .map { HajinStashGrid.Tile(row: gridRows, column: $0.column, id: $0.id, confidence: $0.confidence, count: $0.count,
                                       image: $0.image, guess: $0.guess, guessConfidence: $0.guessConfidence, place: $0.place) }
            .map { ($0, $0.place ?? quad(secureCorners, row: 0, column: $0.column, rows: 1)) }
        var result = HajinPostMatchResult()
        for (t, place) in tiles {
            switch t.id {
            case "empty": continue
            case "blueprint":
                if let picture = t.image {
                    result.blueprints.append(.init(image: picture, guess: t.guess, sure: t.guessConfidence >= 0.6, place: place))
                }
                continue
            case "weapon-manual": result.manuals += 1; continue
            default: break
            }
            // A shared picture's class is named after its first item
            let id = t.id.hasPrefix("x-") ? String(t.id.dropFirst(2)) : t.id
            // Gone by the time you're back: plates are dropped, and dog
            // tags and Lieutenant tag cases are cashed in on exfil
            if discarded(id) { continue }
            // A wild guess (a weapon or gear the model doesn't know) is
            // left out rather than offered as something it isn't
            guard t.id != "other", t.confidence >= 0.3, guide?.item(id) != nil else { result.unread += 1; continue }
            result.counts[id, default: 0] += t.count ?? 1
            result.places[id, default: []].append(place)
            // Where it first is, reading across then down
            result.order[id] = min(result.order[id] ?? .max, t.row * 100 + t.column)
            if t.count == nil || t.confidence < 0.5 { result.unsure.insert(id) }
        }
        result.resources = resources(lines)
        return result
    }

    /// One tile's four corners (TL, TR, BR, BL) inside a framed grid, as
    /// fractions of the photo.
    static func quad(_ k: [CGPoint], row: Int, column: Int, rows: Int) -> [CGPoint] {
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let top = CGPoint(x: k[0].x + (k[1].x - k[0].x) * u, y: k[0].y + (k[1].y - k[0].y) * u)
            let bottom = CGPoint(x: k[3].x + (k[2].x - k[3].x) * u, y: k[3].y + (k[2].y - k[3].y) * u)
            return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
        }
        let u0 = CGFloat(column) / CGFloat(columns), u1 = CGFloat(column + 1) / CGFloat(columns)
        let v0 = CGFloat(row) / CGFloat(max(rows, 1)), v1 = CGFloat(row + 1) / CGFloat(max(rows, 1))
        return [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
    }

    /// Never reaches the stash: armor plates, dog tags, Lieutenant tag cases.
    static func discarded(_ id: String) -> Bool {
        id == "armor-plate" || id.contains("dog-tag")
    }
}

struct HajinPostMatchResult: Identifiable {
    let id = UUID()
    var counts: [String: Int] = [:]
    var unsure: Set<String> = []
    var resources: [String: Int] = [:]
    /// Where each item's tiles are on the photo (four corners each, as
    /// fractions), for the review to light up
    var places: [String: [[CGPoint]]] = [:]
    /// Each item's first tile, row * 100 + column, to list them in the
    /// backpack's own order
    var order: [String: Int] = [:]

    /// A blueprint tile, as read: the picture, and the model's guess at it.
    struct Blueprint: Identifiable {
        let id = UUID()
        let image: CGImage
        let guess: String?
        /// Sure enough to start ticked
        let sure: Bool
        /// Its tile on the photo
        var place: [CGPoint]? = nil
    }
    var blueprints: [Blueprint] = []
    /// Weapon manuals read
    var manuals = 0
    /// Tiles with something on them the reader couldn't name (a weapon, say)
    var unread = 0

    #if DEBUG
    /// SS_POSTMATCH_SAMPLE=1: a large backpack as read on a device, for
    /// the review's layout in the simulator (which can't run the icon model)
    static var sample: HajinPostMatchResult {
        var r = HajinPostMatchResult()
        r.counts = ["ballistic-flight-logs": 9, "nuclear-program-files": 5, "degraded-execution-footage": 4, "electronic-sensors": 1,
                    "control-unit": 1, "regional-combat-notes": 6, "rigid-synthetics": 6, "stim": 2, "cpu": 1, "encrypted-archive": 7,
                    "sanctioned-assassination-list": 1, "binding-catalyst": 1, "cipher-code-ledger": 2, "infantry-invasion-plans": 2, "traindepot-storage-room": 1, "bank-branch-vault-access": 1]
        r.unsure = ["electronic-sensors"]
        r.places = ["ballistic-flight-logs": [HajinBackpack.quad([CGPoint(x: 0.1, y: 0.15), CGPoint(x: 0.85, y: 0.15), CGPoint(x: 0.85, y: 0.6), CGPoint(x: 0.1, y: 0.6)], row: 0, column: 0, rows: 2)]]
        r.resources = ["synthetics": 43, "electronics": 10, "chemicals": 29, "metals": 80]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60))
        let blue = renderer.image { ctx in UIColor(red: 0.1, green: 0.35, blue: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60)) }.cgImage!
        r.blueprints = [.init(image: blue, guess: "drill-charge", sure: true), .init(image: blue, guess: "bomb-glider", sure: false),
                        .init(image: blue, guess: nil, sure: false)]
        r.manuals = 2
        r.unread = 1
        return r
    }
    #endif
}

/// After a match: what was brought out. Each item splits into what's still
/// needed (Keep) and the spare (Sold), by the same rules as Spare to sell;
/// the player can switch either. Update adds what's kept, the resources and
/// the blueprints ticked off; whatever's sold never goes in.
struct HajinPostMatchReview: View {
    let result: HajinPostMatchResult
    var onDone: (() -> Void)? = nil
    /// The backpack photo, over the list (beside it on a wide screen held
    /// sideways): tap an item to light its tiles
    var photo: UIImage? = nil
    @EnvironmentObject private var store: HajinStore
    /// What was read, with the player's swaps applied
    @State private var counts: [String: Int]
    @State private var unsure: Set<String>
    /// Each item's tiles on the photo, swaps applied
    @State private var places: [String: [[CGPoint]]]
    @State private var order: [String: Int]
    /// Items a misread was swapped to
    @State private var swapped: Set<String> = []
    /// The row whose item is being swapped
    @State private var swapping: HajinGuide.Item?
    /// The item (or "bp:" and a blueprint's id) lit on the photo
    @State private var highlighted: String?
    /// The row tapped open, showing its fixes
    @State private var opened: String?
    @State private var size: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    /// Rows the player has switched away from the suggestion
    @State private var flipped: Set<String> = []
    /// Misreads the player has taken out
    @State private var removed: Set<String> = []
    @State private var edited: [String: Int] = [:]
    @State private var editing: HajinGuide.Item?
    @State private var editText = ""
    /// Which blueprint each blueprint tile is, as picked (nil: not ticked)
    @State private var picked: [UUID: String] = [:]
    @State private var pickedReady = false

    init(result: HajinPostMatchResult, onDone: (() -> Void)? = nil, photo: UIImage? = nil) {
        self.result = result
        self.onDone = onDone
        self.photo = photo
        _counts = State(initialValue: result.counts)
        _unsure = State(initialValue: result.unsure)
        _places = State(initialValue: result.places)
        _order = State(initialValue: result.order)
    }

    private struct Row {
        let item: HajinGuide.Item
        let count: Int
        /// The spare part (suggested Sold) rather than the needed part
        let spare: Bool
        var key: String { item.id + (spare ? "#spare" : "#needed") }
    }

    /// Stash items, split into what's still needed and the spare, in the
    /// backpack's order (across, then down), as the stash review lists them.
    private var rows: [Row] {
        guard let guide = store.guide else { return [] }
        let need = store.keepNeeds()
        var out: [Row] = []
        for (id, read) in counts where !removed.contains(id) {
            guard let item = guide.item(id), HajinStore.inStash(item), item.kind != "Resource" else { continue }
            let count = edited[id] ?? read
            let short = max(0, (need[id] ?? 0) - store.count(of: id))
            let keep = (item.value ?? 0) > 0 ? min(count, short) : count
            if count - keep > 0 { out.append(Row(item: item, count: count - keep, spare: true)) }
            if keep > 0 { out.append(Row(item: item, count: keep, spare: false)) }
        }
        return out.sorted { a, b in
            let x = order[a.item.id] ?? .max, y = order[b.item.id] ?? .max
            if x != y { return x < y }
            if a.item.id != b.item.id { return a.item.name.resolved < b.item.name.resolved }
            return a.spare && !b.spare
        }
    }

    /// Everything else read: gear and the like, which My stash doesn't
    /// count. Keys are apart: they share a few pictures, so which key it is
    /// can't be told.
    private var gear: [(item: HajinGuide.Item, count: Int)] {
        guard let guide = store.guide else { return [] }
        return counts.compactMap { id, n in
            guard !removed.contains(id), let item = guide.item(id), !HajinStore.inStash(item), item.kind != "Key" else { return nil }
            return (item, edited[id] ?? n)
        }
        .sorted { (order[$0.item.id] ?? .max, $0.item.name.resolved) < (order[$1.item.id] ?? .max, $1.item.name.resolved) }
    }

    /// Keys read, as one count, and where they all are.
    private var keys: (count: Int, places: [[CGPoint]]) {
        guard let guide = store.guide else { return (0, []) }
        var count = 0, at: [[CGPoint]] = []
        for (id, n) in counts where !removed.contains(id) && guide.item(id)?.kind == "Key" {
            count += edited[id] ?? n
            at += places[id] ?? []
        }
        return (count, at)
    }

    private func sells(_ row: Row) -> Bool { row.spare != flipped.contains(row.key) }

    var body: some View {
        let all = rows
        let sold = all.filter(sells)
        let total = sold.reduce(0) { $0 + ($1.item.value ?? 0) * $1.count }
        let kept = all.filter { !sells($0) }
        let ticked = picked.values.filter { !store.hasBlueprint($0) }
        NavigationStack {
            List {
                summary(sold: sold.reduce(0) { $0 + $1.count }, total: total)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if !result.resources.isEmpty {
                    Section {
                        resourcesRow
                    } header: {
                        Text("mw4.ui.hajin.resources".localized())
                    } footer: {
                        Text("mw4.ui.postmatch.resources_footer".localized())
                    }
                }
                if !all.isEmpty {
                    Section {
                        ForEach(all, id: \.key) { row in itemRow(row) }
                    } header: {
                        Text("mw4.ui.postmatch.items".localized())
                    } footer: {
                        Text("mw4.ui.postmatch.items_footer".localized())
                    }
                }
                if !result.blueprints.isEmpty {
                    Section {
                        ForEach(result.blueprints) { blueprint in blueprintRow(blueprint) }
                    } header: {
                        Text(String(format: "mw4.ui.postmatch.blueprints".localized(), result.blueprints.count))
                    } footer: {
                        Text("mw4.ui.postmatch.blueprints_footer".localized())
                    }
                }
                if result.manuals > 0 {
                    Section { manualRow }
                }
                if !gear.isEmpty || keys.count > 0 {
                    Section("mw4.ui.postmatch.gear".localized()) {
                        ForEach(gear, id: \.item.id) { line in
                            HStack(spacing: 12) {
                                findableTile(line.item, size: 32)
                                Text(line.item.name.resolved).font(.subheadline).foregroundStyle(Color.appInk)
                                Spacer()
                                Text("×\(line.count)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInkMuted)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { light(line.item.id) }
                            .listRowBackground(highlighted == line.item.id ? Color.accentDMZ.opacity(0.14) : nil)
                            .swipeActions {
                                Button("mw4.ui.postmatch.remove".localized(), role: .destructive) { removed.insert(line.item.id) }
                            }
                        }
                        if keys.count > 0 { keysRow }
                    }
                }
                if result.unread > 0 {
                    Label(String(format: "mw4.ui.postmatch.unread".localized(), result.unread), systemImage: "questionmark.square.dashed")
                        .font(.footnote)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .alert(editing?.name.resolved ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("0", text: $editText).keyboardType(.numberPad)
                Button("mw4.ui.hajin.save".localized()) {
                    if let item = editing, let n = Int(editText) { edited[item.id] = n }
                    editing = nil
                }
                Button("mw4.ui.hajin.cancel".localized(), role: .cancel) { editing = nil }
            }
            // The photo over the list, to compare (beside it on a wide
            // screen held sideways)
            .modifier(HajinPhotoBeside(size: size) {
                if let photo {
                    HajinZoomPhoto(image: photo, marks: highlighted.map(marks) ?? [])
                }
            })
            .sheet(item: $swapping) { item in
                HajinItemPicker(current: item) { picked in
                    swap(item.id, to: picked)
                    swapping = nil
                }
            }
            .navigationTitle("mw4.ui.postmatch.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Over the framing screen: back to it, to fix the frame
                    // and read again (Cancel there ends the scan)
                    if photo != nil {
                        Button { dismiss() } label: {
                            Label("mw4.ui.hajin.back".localized(), systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    } else {
                        Button("mw4.ui.hajin.cancel".localized()) { dismiss(); onDone?() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.scan_apply".localized()) { apply(kept, blueprints: ticked, sold: total) }
                        .disabled(kept.isEmpty && result.resources.isEmpty && ticked.isEmpty && total == 0)
                }
            }
            .onAppear {
                // Sure guesses start ticked; the rest wait for a pick
                guard !pickedReady else { return }
                pickedReady = true
                for blueprint in result.blueprints where blueprint.sure {
                    if let guess = blueprint.guess { picked[blueprint.id] = guess }
                }
                // Start with the first item that can be found on the photo
                // selected: lit, its fixes open
                if photo != nil { highlighted = all.first { places[$0.item.id] != nil }?.item.id; opened = highlighted }
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { size = $0 }
        })
        .presentationDetents([.large])
        // With the photo: a drag on the list scrolls it, never moves the sheet
        .modifier(HajinScrollsNotSheet(on: photo != nil))
    }

    /// Every key, unnamed: a key's picture doesn't say which it is.
    private var keysRow: some View {
        HStack(spacing: 12) {
            HajinCardSymbol("key.fill")
            Text("mw4.ui.postmatch.keys".localized()).font(.subheadline).foregroundStyle(Color.appInk)
            Spacer()
            Text("×\(keys.count)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInkMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture { light("keys") }
        .listRowBackground(highlighted == "keys" ? Color.accentDMZ.opacity(0.14) : nil)
        .swipeActions {
            Button("mw4.ui.postmatch.remove".localized(), role: .destructive) {
                for (id, _) in counts where store.guide?.item(id)?.kind == "Key" { removed.insert(id) }
            }
        }
    }

    /// Where a lit row's tiles are on the photo.
    private func marks(_ key: String) -> [[CGPoint]] {
        guard photo != nil else { return [] }
        if key == "keys" { return keys.places }
        if key.hasPrefix("bp:") {
            return result.blueprints.first { "bp:\($0.id)" == key }?.place.map { [$0] } ?? []
        }
        return places[key] ?? []
    }

    /// Lights a row's tiles on the photo, or puts them out.
    private func light(_ key: String) {
        guard !marks(key).isEmpty else { return }
        Haptics.step()
        withAnimation(.snappy) { highlighted = highlighted == key ? nil : key; opened = nil }
    }

    /// The item's picture, with a viewfinder badge when its tiles can be
    /// lit on the photo.
    private func findableTile(_ item: HajinGuide.Item, size: CGFloat) -> some View {
        HajinItemTile(item: item, size: size)
            .overlay(alignment: .bottomTrailing) {
                if !marks(item.id).isEmpty {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(highlighted == item.id ? Color.accentDMZ : Color.black.opacity(0.6)))
                        .offset(x: 4, y: 4)
                }
            }
    }

    /// Everything read as `id` is really `to`: its count, tiles and any
    /// edit move over, and it's no longer one to check.
    private func swap(_ id: String, to: String) {
        Haptics.step()
        counts[to, default: 0] += counts[id] ?? 0
        counts[id] = nil
        places[to, default: []] += places[id] ?? []
        places[id] = nil
        if let at = order[id] { order[to] = min(order[to] ?? .max, at); order[id] = nil }
        if let n = edited[id] { edited[to] = (edited[to] ?? 0) + n; edited[id] = nil }
        unsure.remove(id)
        removed.remove(to)
        flipped = flipped.filter { !$0.hasPrefix(id + "#") }
        swapped.remove(id)
        swapped.insert(to)
        if highlighted == id { highlighted = to }
        if opened == id { opened = to }
    }

    /// "Sell 6 · $41,200": the sell pile at a glance.
    private func summary(sold: Int, total: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(sold > 0 ? HajinVerdict.sellColor : Color.appInkMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(sold > 0 ? String(format: "mw4.ui.postmatch.sell_total".localized(), sold) : "mw4.ui.postmatch.sell_none".localized())
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
                if total > 0 {
                    Text("mw4.ui.postmatch.sell_cash".localized())
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                }
            }
            Spacer(minLength: 8)
            if total > 0 {
                Text("$\(total.formatted())")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(HajinVerdict.sellColor)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .borderedCard(accent: total > 0 ? HajinVerdict.sellColor : nil)
        .animation(.snappy, value: total)
    }

    private var resourcesRow: some View {
        HStack(spacing: 14) {
            ForEach(["synthetics", "electronics", "chemicals", "metals"], id: \.self) { id in
                if let n = result.resources[id], let item = store.guide?.item(id) {
                    HStack(spacing: 6) {
                        HajinItemTile(item: item, size: 26)
                        Text("+\(n)").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInk)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.name.resolved) +\(n)")
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// One item: its picture, name and a line of what it is (count, worth,
    /// a check mark when the read was weak), and Sold | Keep. Tapped, it's
    /// lit on the photo and opens its fixes: the right item, or the count.
    private func itemRow(_ row: Row) -> some View {
        let check = unsure.contains(row.item.id) && edited[row.item.id] == nil
        let wasSwapped = swapped.contains(row.item.id)
        let selected = highlighted == row.item.id
        let open = opened == row.item.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    findableTile(row.item, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk).lineLimit(2)
                        HStack(spacing: 6) {
                            Text("×\(row.count)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                            if let value = row.item.value, value > 0 {
                                Text("$\((value * row.count).formatted())").font(.caption)
                            }
                            if wasSwapped {
                                Image(systemName: "arrow.left.arrow.right").font(.caption2.weight(.bold)).foregroundStyle(Color.accentDMZ)
                                    .accessibilityLabel("mw4.ui.hajin.scan_swapped".localized())
                            } else if check {
                                Text("mw4.ui.hajin.scan_check".localized())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color(red: 0.96, green: 0.66, blue: 0.24)))
                            }
                        }
                        .foregroundStyle(Color.appInkMuted)
                    }
                    Spacer(minLength: 6)
                }
                // Tap the item to see its tiles on the photo, and its fixes
                .contentShape(Rectangle())
                .onTapGesture { select(row.item.id) }
                soldKeep(row)
            }
            if open {
                HStack(spacing: 8) {
                    if photo != nil {
                        fixButton("mw4.ui.hajin.scan_change", "arrow.left.arrow.right") { swapping = row.item }
                    }
                    fixButton("mw4.ui.hajin.scan_edit", "pencil") {
                        editText = "\(edited[row.item.id] ?? counts[row.item.id] ?? row.count)"; editing = row.item
                    }
                    fixButton("mw4.ui.postmatch.remove", "trash") { removed.insert(row.item.id) }
                }
                .transition(.opacity)
            }
        }
        .listRowBackground(selected ? Color.accentDMZ.opacity(0.14) : nil)
        .swipeActions {
            Button("mw4.ui.postmatch.remove".localized(), role: .destructive) { removed.insert(row.item.id) }
        }
    }

    /// A small fix under the selected row.
    private func fixButton(_ key: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Three to a row, sharing it: one line each
            Label(key.localized(), systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentDMZ.opacity(0.14)))
        }
        .buttonStyle(.borderless)
    }

    /// Taps a row: selected, its tiles lit and its fixes open in one go
    /// (tap again to let go of it).
    private func select(_ key: String) {
        Haptics.step()
        withAnimation(.snappy) {
            if opened == key { opened = nil; highlighted = nil } else { opened = key; highlighted = key }
        }
    }

    /// Sold | Keep, the chosen one filled.
    private func soldKeep(_ row: Row) -> some View {
        let sell = sells(row)
        return HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { option in
                let on = option == sell
                Button {
                    guard !on else { return }
                    Haptics.step()
                    if flipped.contains(row.key) { flipped.remove(row.key) } else { flipped.insert(row.key) }
                } label: {
                    Text((option ? "mw4.ui.postmatch.sold" : "mw4.ui.postmatch.keep").localized())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(on ? Color.black.opacity(0.85) : Color.appInkMuted)
                        .frame(minWidth: 48, minHeight: 32)
                        .background(Capsule().fill(on ? (option ? HajinVerdict.sellColor : Color.accentDMZ) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.appSurface2))
    }

    /// A blueprint tile as it was in the photo, and which blueprint it is:
    /// the guess, or one picked from those still to find. Picked = ticked off.
    private func blueprintRow(_ blueprint: HajinPostMatchResult.Blueprint) -> some View {
        let choice = picked[blueprint.id]
        let item = choice.flatMap { store.guide?.item($0) }
        let candidates = (store.guide?.items ?? []).filter { $0.blueprint == true && !store.hasBlueprint($0.id) }
            .sorted { $0.name.resolved < $1.name.resolved }
        return HStack(spacing: 12) {
            Image(decorative: blueprint.image, scale: 1)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentDMZ, lineWidth: highlighted == "bp:\(blueprint.id)" ? 2 : 0))
                // Tap the tile to see it on the photo
                .onTapGesture { light("bp:\(blueprint.id)") }
            Menu {
                if let guess = blueprint.guess, let guessed = store.guide?.item(guess) {
                    Button { picked[blueprint.id] = guess } label: {
                        Label(guessed.name.resolved, systemImage: "sparkles")
                    }
                    Divider()
                }
                ForEach(candidates, id: \.id) { candidate in
                    Button(candidate.name.resolved) { picked[blueprint.id] = candidate.id }
                }
                if choice != nil {
                    Divider()
                    Button("mw4.ui.postmatch.blueprint_clear".localized(), role: .destructive) { picked[blueprint.id] = nil }
                }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item?.name.resolved ?? "mw4.ui.postmatch.blueprint_pick".localized())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item == nil ? Color.accentDMZ : Color.appInk)
                        if let id = choice, store.hasBlueprint(id) {
                            Text("mw4.ui.postmatch.blueprint_had".localized()).font(.caption2).foregroundStyle(Color.appInkMuted)
                        } else if let guess = blueprint.guess, choice == nil, let guessed = store.guide?.item(guess) {
                            Text(String(format: "mw4.ui.postmatch.blueprint_guess".localized(), guessed.name.resolved))
                                .font(.caption2).foregroundStyle(Color.appInkMuted)
                        }
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: item == nil ? "circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(item == nil ? Color.appInkMuted : Color.accentDMZ)
        }
    }

    /// Weapon manuals picked up: tick each gun in Gunsmith prices.
    private var manualRow: some View {
        NavigationLink {
            if let section = store.guide?.guide.first(where: { $0.id == "gunsmith" }) {
                GuideSectionView(section: section)
            }
        } label: {
            HStack(spacing: 12) {
                HajinCardSymbol("book.closed.fill")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("mw4.ui.postmatch.manual_found".localized())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        if result.manuals > 1 {
                            Text("×\(result.manuals)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInkMuted)
                        }
                    }
                    Text("mw4.ui.postmatch.manual_hint".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
                }
            }
        }
        .listRowBackground(Color.accentDMZ.opacity(0.15))
    }

    private func apply(_ kept: [Row], blueprints: [String], sold: Int) {
        Haptics.step()
        // What's sold is paid into DMZ Cash
        if sold > 0 { store.setCash(store.cash + sold) }
        var counts: [String: Int] = [:]
        for row in kept { counts[row.item.id] = (counts[row.item.id] ?? store.count(of: row.item.id)) + row.count }
        for (id, n) in result.resources { counts[id] = store.count(of: id) + n }
        store.applyScannedCounts(counts)
        for id in Set(blueprints) where !store.hasBlueprint(id) { store.toggle(HajinStore.blueprintKey(id)) }
        dismiss()
        onDone?()
    }
}

