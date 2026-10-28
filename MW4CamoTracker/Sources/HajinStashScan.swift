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

/// "Not this item?": every item My stash counts, the same kind as the
/// misread one first, to pick the one it really is.
struct HajinItemPicker: View {
    let current: HajinGuide.Item
    let pick: (String) -> Void
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let needle = query.lowercased()
        let all = (store.guide?.items ?? [])
            .filter { HajinStore.inStash($0) && $0.kind != "Resource" && $0.id != current.id }
            .filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
            .sorted { $0.name.resolved < $1.name.resolved }
        let alike = all.filter { $0.kind == current.kind }
        let rest = all.filter { $0.kind != current.kind }
        NavigationStack {
            List {
                if !alike.isEmpty { Section(current.kind == "Valuable" ? "mw4.ui.hajin.valuables".localized() : "mw4.ui.hajin.ingredients".localized()) { rowsView(alike) } }
                if !rest.isEmpty { Section(current.kind == "Valuable" ? "mw4.ui.hajin.ingredients".localized() : "mw4.ui.hajin.valuables".localized()) { rowsView(rest) } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_guide".localized())
            .navigationTitle("mw4.ui.hajin.scan_swap_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func rowsView(_ items: [HajinGuide.Item]) -> some View {
        ForEach(items) { item in
            Button { pick(item.id) } label: {
                HStack(spacing: 12) {
                    HajinItemTile(item: item, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                        if let rarity = item.rarity {
                            Text(rarity).font(.caption).foregroundStyle(HajinRarity.color(rarity))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The review's photo: on top of the counts, or to their left when the
/// screen is wide and held sideways (an iPad in landscape).
struct HajinPhotoBeside<P: View>: ViewModifier {
    let size: CGSize
    @ViewBuilder let photo: () -> P

    func body(content: Content) -> some View {
        if size.width >= 700 && size.width > size.height {
            content.safeAreaInset(edge: .leading, spacing: 0) {
                photo()
                    .frame(width: size.width * 0.55)
                    .overlay(alignment: .trailing) { Rectangle().fill(Color.appSurface2).frame(width: 1) }
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                photo()
                    .frame(height: max(size.height, 1) * 0.45)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.appSurface2).frame(height: 1) }
            }
        }
    }
}

/// A sheet whose content scrolls rather than resizing or closing it.
struct HajinScrollsNotSheet: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on, #available(iOS 16.4, *) {
            content.presentationContentInteraction(.scrolls).interactiveDismissDisabled()
        } else {
            content
        }
    }
}

/// A photo to pinch and drag (iOS's own zooming, as in Photos): double-tap
/// zooms in there or back out, and lit tiles are zoomed to.
struct HajinZoomPhoto: View {
    let image: UIImage
    /// Tiles to light up, each four corners as fractions of the photo
    var marks: [[CGPoint]] = []
    @State private var zoomed = false

    var body: some View {
        HajinZoomScroll(image: image, marks: marks, zoomed: $zoomed)
            .background(Color.black)
            .overlay(alignment: .bottomTrailing) {
                if !zoomed {
                    Label("mw4.ui.hajin.zoom_hint".localized(), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct HajinZoomScroll: UIViewRepresentable {
    let image: UIImage
    let marks: [[CGPoint]]
    @Binding var zoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Lays the photo out once it has a size (it has none when made)
    final class Scroll: UIScrollView {
        var onLayout: ((UIScrollView) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = Scroll()
        let coordinator = context.coordinator
        scroll.onLayout = { [weak coordinator] scroll in
            guard let coordinator else { return }
            coordinator.layout(scroll)
            coordinator.show(coordinator.parent.marks, in: scroll)
        }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        let content = context.coordinator.content
        content.image = image
        content.contentMode = .scaleToFill
        content.isUserInteractionEnabled = true
        content.layer.addSublayer(context.coordinator.marksLayer)
        scroll.addSubview(content)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.layout(scroll)
        context.coordinator.show(marks, in: scroll)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: HajinZoomScroll
        let content = UIImageView()
        let marksLayer = CAShapeLayer()
        private var shown: [[CGPoint]]?
        private var laidOutFor: CGSize = .zero

        init(_ parent: HajinZoomScroll) {
            self.parent = parent
            marksLayer.fillColor = UIColor(Color.accentDMZ.opacity(0.25)).cgColor
            marksLayer.strokeColor = UIColor(Color.accentDMZ).cgColor
            marksLayer.lineWidth = 2.5
        }

        /// The photo at its fitted size in the middle of the box, at 1x.
        func layout(_ scroll: UIScrollView) {
            let box = scroll.bounds.size
            guard box.width > 0, box.height > 0, box != laidOutFor else { return }
            laidOutFor = box
            scroll.zoomScale = 1
            let size = parent.image.size
            let s = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
            content.frame = CGRect(x: 0, y: 0, width: size.width * s, height: size.height * s)
            scroll.contentSize = content.frame.size
            marksLayer.frame = content.bounds
            center(scroll)
            shown = nil
        }

        /// Draws the lit tiles and zooms to fit them (or back out with none).
        func show(_ marks: [[CGPoint]], in scroll: UIScrollView) {
            guard laidOutFor != .zero, shown != marks else { return }
            shown = marks
            let w = content.bounds.width, h = content.bounds.height
            let path = UIBezierPath()
            for quad in marks where quad.count == 4 {
                path.move(to: CGPoint(x: quad[0].x * w, y: quad[0].y * h))
                for p in quad.dropFirst() { path.addLine(to: CGPoint(x: p.x * w, y: p.y * h)) }
                path.close()
            }
            marksLayer.path = path.cgPath
            let points = marks.flatMap { $0 }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else {
                scroll.setZoomScale(1, animated: true)
                return
            }
            let rect = CGRect(x: minX * w, y: minY * h, width: (maxX - minX) * w, height: (maxY - minY) * h)
            // Room round the tiles, and no closer than 4x
            let side = max(rect.width, rect.height, min(w, h) / 4) * 1.6
            scroll.zoom(to: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), animated: true)
        }

        /// Smaller than the box: keep it in the middle.
        private func center(_ scroll: UIScrollView) {
            let box = scroll.bounds.size, size = scroll.contentSize
            scroll.contentInset = UIEdgeInsets(top: max(0, (box.height - size.height) / 2), left: max(0, (box.width - size.width) / 2),
                                               bottom: 0, right: 0)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
            // Lines the same width on screen at any zoom
            marksLayer.lineWidth = 2.5 / scrollView.zoomScale
            let zoomed = scrollView.zoomScale > 1.01
            if zoomed != parent.zoomed { DispatchQueue.main.async { self.parent.zoomed = zoomed } }
        }

        @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let p = tap.location(in: content)
                let w = content.bounds.width / 3, h = content.bounds.height / 3
                scroll.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
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
    /// Stash photos: the photo, in the top half to check the counts against
    var photo: UIImage? = nil
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var skip: Set<String> = []
    @State private var edited: [String: Int] = [:]
    @State private var editing: HajinGuide.Item?
    @State private var editText = ""
    @State private var skipCash = false
    @State private var skipLevel = false
    @State private var detent = PresentationDetent.medium
    /// The item whose tiles are lit on the photo
    @State private var highlighted: String?
    /// After Update: offer to send the photo and corrections, unless the
    /// player has said not to ask again
    @AppStorage("mw4_hajin_ask_send_scan") private var askToSend = true
    @State private var asking = false
    @State private var sentState: (had: [String: Int], edited: [String: Int], skipped: Set<String>, swapped: [String: String])?
    @State private var mail: HajinMailDraft?
    @State private var share: [Any]?
    /// Items the player said the reader got wrong: what it read → what it is
    @State private var swaps: [String: String] = [:]
    /// The row whose item is being swapped
    @State private var swapping: HajinGuide.Item?
    /// The screen's size: the photo goes beside the counts when it's wide
    @State private var size: CGSize = .zero

    /// What was read, with the player's swaps applied (a swap onto an item
    /// also read adds the two together)
    private var counts: [String: Int] {
        var out: [String: Int] = [:]
        for (id, n) in found { out[swaps[id] ?? id, default: 0] += n }
        return out
    }

    /// The id the reader actually read for a row (itself unless swapped in).
    private func source(_ id: String) -> String {
        found[id] != nil ? id : (swaps.first { $0.value == id }?.key ?? id)
    }

    private var rows: [(item: HajinGuide.Item, now: Int, read: Int)] {
        // Only what My stash tracks: resources, ingredients and valuables.
        // The photo reader also recognises keys and gear, and leaves them out.
        counts.compactMap { id, n in store.guide?.item(id).flatMap { HajinStore.inStash($0) ? $0 : nil }
            .map { ($0, store.count(of: id), edited[id] ?? n) } }
            // The photo's grid order (a 3D Printer screen: ones to check
            // first, then the least sure). Ordered by what was read, not
            // edits, so a row stays put while you change it.
            .sorted(by: before)
    }

    private func before(_ a: (item: HajinGuide.Item, now: Int, read: Int), _ b: (item: HajinGuide.Item, now: Int, read: Int)) -> Bool {
        let x = order(a.item.id), y = order(b.item.id)
        return x != y ? x < y : a.item.name.resolved < b.item.name.resolved
    }

    private func order(_ id: String) -> (Int, Int) {
        // A swapped row keeps the place of the item it was read as
        let id = source(id)
        // A stash photo: the grid's order, A1 across then down, as on the
        // photo above (resources, read from the text, first)
        if let tiles = report?.tiles {
            let first = tiles.filter { $0.id == id }.map { $0.row * 100 + $0.column }.min()
            return (first.map { $0 + 1 } ?? 0, 0)
        }
        let sure = sureness[id].map { Int(($0 * 100).rounded()) } ?? 100
        if unsure.contains(id) { return (0, sure) }
        if sure < 100 { return (1, sure) }
        return (store.count(of: id) == found[id] ? 3 : 2, sure)
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
        let findable = !marks(for: row.item.id).isEmpty
        HStack(spacing: 10) {
            HStack(spacing: 10) {
            HajinItemTile(item: row.item, size: 32)
                .overlay(alignment: .bottomTrailing) {
                    if findable {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(highlighted == row.item.id ? Color.accentDMZ : Color.black.opacity(0.6)))
                            .offset(x: 4, y: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                    .lineLimit(2)
                let swapped = Set(swaps.values).contains(row.item.id)
                HStack(spacing: 6) {
                    if swapped {
                        Label("mw4.ui.hajin.scan_swapped".localized(), systemImage: "arrow.left.arrow.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentDMZ)
                    } else if unsure.contains(row.item.id) && edited[row.item.id] == nil {
                        Text("mw4.ui.hajin.scan_check".localized().uppercased())
                            .font(.system(size: 10, weight: .bold)).tracking(0.6)
                            .foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.24))
                    }
                    if !swapped, let sure = sureness[row.item.id] {
                        Text(String(format: "mw4.ui.hajin.scan_sure".localized(), stacks[row.item.id] ?? 1, Int((sure * 100).rounded())))
                            .font(.caption2)
                            .foregroundStyle(sure < 0.5 ? Color(red: 0.96, green: 0.66, blue: 0.24) : Color.appInkMuted)
                    }
                }
                // Read off the photo's tiles: wrong item? pick the right one
                // (on the item tapped, so the list isn't full of it)
                if highlighted == row.item.id && (swapped || sureness[row.item.id] != nil) {
                    Button { swapping = row.item } label: {
                        Text("mw4.ui.hajin.scan_not_this".localized())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentDMZ)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 6)
            }
            // Tap the item to see its tiles on the photo
            .contentShape(Rectangle())
            .onTapGesture {
                guard findable else { return }
                Haptics.step()
                withAnimation(.snappy) { highlighted = highlighted == row.item.id ? nil : row.item.id }
            }
            if !same {
                // What the stash has now, then the count it becomes
                Text("\(row.now) →")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(1).fixedSize()
            }
            countControl(row, on: on || same)
            if same {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(HajinStore.printableGreen)
                    .frame(width: 24)
                    .accessibilityLabel("mw4.ui.hajin.scan_same".localized())
            } else {
                // Include or leave out this change
                Button {
                    Haptics.step()
                    if skip.contains(row.item.id) { skip.remove(row.item.id) } else { skip.insert(row.item.id) }
                } label: {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? Color.accentDMZ : Color.appInkMuted)
                        .frame(width: 24, height: 32)
                }
                .buttonStyle(.borderless)
            }
        }
        .listRowBackground(highlighted == row.item.id ? Color.accentDMZ.opacity(0.14) : nil)
    }

    /// Where an item's tiles are in the photo: each tile's four corners, as
    /// fractions of the photo, from the grid the player framed.
    private func marks(for id: String) -> [[CGPoint]] {
        guard photo != nil, let report, report.corners.count == 4 else { return [] }
        let tiles = report.tiles
        let rows = (tiles.map(\.row).max() ?? 0) + 1, columns = max((tiles.map(\.column).max() ?? 0) + 1, HajinStashGrid.columns)
        let k = report.corners
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let top = CGPoint(x: k[0].x + (k[1].x - k[0].x) * u, y: k[0].y + (k[1].y - k[0].y) * u)
            let bottom = CGPoint(x: k[3].x + (k[2].x - k[3].x) * u, y: k[3].y + (k[2].y - k[3].y) * u)
            return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
        }
        return tiles.filter { (swaps[$0.id] ?? $0.id) == id }.map { t in
            // Where the tile was really read, from its own borders
            if let place = t.place { return place }
            let u0 = CGFloat(t.column) / CGFloat(columns), u1 = CGFloat(t.column + 1) / CGFloat(columns)
            let v0 = CGFloat(t.row) / CGFloat(rows), v1 = CGFloat(t.row + 1) / CGFloat(rows)
            return [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
        }
    }

    /// − count +: steps the count read from the photo, or tap the number
    /// to type it. Changing it includes the row again.
    private func countControl(_ row: (item: HajinGuide.Item, now: Int, read: Int), on: Bool) -> some View {
        HStack(spacing: 0) {
            Button { setCount(row.item.id, row.read - 1) } label: {
                Image(systemName: "minus").font(.footnote.weight(.bold)).frame(width: 28, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(row.read == 0)
            Button { editText = "\(row.read)"; editing = row.item } label: {
                Text("\(row.read)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(on ? Color.appInk : Color.appInkMuted)
                    .strikethrough(!on)
                    .lineLimit(1).fixedSize()
                    .frame(minWidth: 30, minHeight: 30)
            }
            .buttonStyle(.borderless)
            Button { setCount(row.item.id, row.read + 1) } label: {
                Image(systemName: "plus").font(.footnote.weight(.bold)).frame(width: 28, height: 30)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(Color.accentDMZ)
        .background(Capsule().fill(Color.appSurface2))
        .fixedSize()
    }

    private func setCount(_ id: String, _ count: Int) {
        Haptics.step()
        edited[id] = max(0, count)
        skip.remove(id)
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
                    .sorted { HajinStore.resourceRank($0.item.id) < HajinStore.resourceRank($1.item.id) }
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
            }
            // The photo over the counts, half and half, to zoom and compare
            // (beside them on a wide screen held sideways)
            .modifier(HajinPhotoBeside(size: size) {
                if let photo {
                    HajinZoomPhoto(image: photo, marks: highlighted.map { marks(for: $0) } ?? [])
                }
            })
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
            .sheet(item: $swapping) { item in
                HajinItemPicker(current: item) { picked in
                    swap(item.id, to: picked)
                    swapping = nil
                }
            }
            .navigationTitle("mw4.ui.hajin.scan_title".localized())
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
                    Button("mw4.ui.hajin.scan_apply".localized()) { apply(changes, cash: cashChange, level: levelChange) }
                        .disabled(changes.isEmpty && cashChange == nil && levelChange == nil)
                }
            }
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { size = geo.size }
                .onChange(of: geo.size) { size = $0 }
        })
        .presentationDetents(photo == nil ? [.medium, .large] : [.large], selection: $detent)
        // With the photo: a drag on the list scrolls it, never moves the sheet
        // (and the photo with it); Cancel closes it
        .modifier(HajinScrollsNotSheet(on: photo != nil))
        .onAppear {
            if photo != nil { detent = .large }
            // Start with the first item that can be found on the photo lit
            if highlighted == nil { highlighted = rows.first { !marks(for: $0.item.id).isEmpty }?.item.id }
        }
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
            sentState = (had, edited, skip, swaps)
            asking = true
        } else {
            finish()
        }
    }

    /// Everything read as `id` (or swapped onto it) is really `to`.
    private func swap(_ id: String, to: String) {
        guard id != to else { return }
        Haptics.step()
        for (from, target) in swaps where target == id { swaps[from] = to }
        if found[id] != nil { swaps[id] = to }
        // Back to what it was read as: no swap at all
        for (from, target) in swaps where from == target { swaps[from] = nil }
        edited[id] = nil; edited[to] = nil
        skip.remove(to)
        if highlighted == id { highlighted = to }
    }

    private func sendReport() {
        guard let report, let state = sentState else { finish(); return }
        switch report.outgoing(had: state.had, edited: state.edited, skipped: state.skipped, swapped: state.swapped) {
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
