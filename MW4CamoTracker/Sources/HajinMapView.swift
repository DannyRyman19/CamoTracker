import SwiftUI
import UIKit

/// What a tap on the map picked: one of the guide's markers or one of the
/// player's own pins.
enum HajinSelection: Hashable, Identifiable {
    case marker(HajinGuide.Marker)
    case pin(UUID)

    var id: String {
        switch self {
        case .marker(let marker): return marker.id
        case .pin(let id): return id.uuidString
        }
    }
}

/// The zoomable Tac Map. UIKit underneath because the markers have to stay
/// the same size on screen while the map scales under them, and SwiftUI's
/// gestures can't zoom a 2660 px image smoothly on an older iPhone.
struct HajinMapView: UIViewRepresentable {
    let guide: HajinGuide
    let image: UIImage
    let hidden: Set<String>
    let pins: [HajinPin]
    let selection: HajinSelection?
    /// Bump `focus.token` to fly to a point (0...1 map coordinates).
    let focus: Focus?
    let onSelect: (HajinSelection?) -> Void
    let onLongPress: (CGPoint) -> Void

    struct Focus: Equatable {
        var point: CGPoint
        var token: Int
    }

    func makeUIView(context: Context) -> HajinMapUIView {
        let view = HajinMapUIView(image: image)
        view.onSelect = onSelect
        view.onLongPress = onLongPress
        return view
    }

    func updateUIView(_ view: HajinMapUIView, context: Context) {
        view.onSelect = onSelect
        view.onLongPress = onLongPress
        view.update(guide: guide, hidden: hidden, pins: pins, selection: selection)
        if let focus, focus != view.lastFocus {
            view.lastFocus = focus
            view.fly(to: focus.point)
        }
    }
}

final class HajinMapUIView: UIView, UIScrollViewDelegate {
    var onSelect: ((HajinSelection?) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var lastFocus: HajinMapView.Focus?
    /// A fly-to asked for before the first layout, run once there's a size.
    private var pendingFocus: CGPoint?

    private let scrollView = UIScrollView()
    private let content = UIView()
    private let imageView: UIImageView
    private let mapSize: CGSize
    /// Every marker view with how far past the whole-map zoom it starts to show.
    private var overlays: [(view: UIView, minZoom: CGFloat)] = []
    private var renderedKey = ""
    private var lastBounds: CGSize = .zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        mapSize = image.size
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.043, green: 0.059, blue: 0.051, alpha: 1)

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        content.frame = CGRect(origin: .zero, size: mapSize)
        imageView.frame = content.bounds
        content.addSubview(imageView)
        scrollView.addSubview(content)
        scrollView.contentSize = mapSize

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        scrollView.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        scrollView.addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.size != lastBounds, bounds.width > 0 else { return }
        let first = lastBounds == .zero
        lastBounds = bounds.size
        // Fit the whole map, and allow zooming in to twice its pixel size
        let fit = min(bounds.width / mapSize.width, bounds.height / mapSize.height)
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 4, 2)
        if first || scrollView.zoomScale < fit {
            // Open a little closer than the whole map, on the city: low
            // enough that a portrait phone doesn't start on the
            // out-of-bounds land along the top edge (a tall screen needs to
            // be in closer before there's any room to scroll down)
            let tall = bounds.height > bounds.width * 1.3
            // A short, wide map (the iPad's guide dragged up) still opens across its width
            scrollView.zoomScale = min(max(fit * (tall ? 2.3 : 1.6), bounds.width / mapSize.width), scrollView.maximumZoomScale)
            centre(on: CGPoint(x: 0.5, y: tall ? 0.72 : 0.55), animated: false)
            #if DEBUG
            // SS_MAP_VIEW=<zoom>,<x>,<y>: frame the map for a store shot
            let v = (ProcessInfo.processInfo.environment["SS_MAP_VIEW"] ?? "").split(separator: ",").compactMap { Double($0) }
            if v.count == 3 {
                scrollView.zoomScale = min(fit * v[0], scrollView.maximumZoomScale)
                centre(on: CGPoint(x: v[1], y: v[2]), animated: false)
            }
            #endif
        } else if scrollView.zoomScale < bounds.width / mapSize.width {
            // Made shorter and wider (the iPad's map and guide divider
            // dragged up): keep the map across the whole width, on the same spot
            let zoom = scrollView.zoomScale
            let middle = CGPoint(x: (scrollView.contentOffset.x + scrollView.bounds.width / 2) / (mapSize.width * zoom),
                                 y: (scrollView.contentOffset.y + scrollView.bounds.height / 2) / (mapSize.height * zoom))
            scrollView.zoomScale = min(bounds.width / mapSize.width, scrollView.maximumZoomScale)
            let fill = scrollView.zoomScale
            let maxX = max(scrollView.contentSize.width - bounds.width, 0)
            let maxY = max(scrollView.contentSize.height - bounds.height, 0)
            scrollView.contentOffset = CGPoint(x: min(max(middle.x * mapSize.width * fill - bounds.width / 2, 0), maxX),
                                               y: min(max(middle.y * mapSize.height * fill - bounds.height / 2, 0), maxY))
        }
        if let pending = pendingFocus {
            pendingFocus = nil
            scrollView.zoomScale = min(fit * 4, scrollView.maximumZoomScale)
            centre(on: pending, animated: false)
        }
        centreContent()
        rescaleOverlays()
    }

    // MARK: Markers

    func update(guide: HajinGuide, hidden: Set<String>, pins: [HajinPin], selection: HajinSelection?) {
        let key = "\(guide.version)|\(hidden.sorted())|\(pins.map { "\($0.id)\($0.x)\($0.y)\($0.title)" })|\(selection?.id ?? "")"
        guard key != renderedKey else { return }
        renderedKey = key
        overlays.forEach { $0.view.removeFromSuperview() }
        overlays = []
        tags = [:]

        // Names first so the icons sit on top of them
        let ordered = guide.markers.sorted { (guide.category($0.cat)?.isLabel ?? false) && !(guide.category($1.cat)?.isLabel ?? false) }
        for marker in ordered where !hidden.contains(marker.cat) {
            guard let category = guide.category(marker.cat) else { continue }
            let selected = selection == .marker(marker)
            let view: UIView
            let minZoom: CGFloat
            if category.isLabel {
                let area = category.id == "area"
                // Area names take their threat colour, Low green to Extreme red
                let colour = marker.threat.map { UIColor(HajinThreat.color($0)) }
                    ?? (area ? .white : UIColor(white: 0.85, alpha: 1))
                view = label(marker.name.resolved, size: area ? 14 : 11, weight: area ? .heavy : .semibold,
                             colour: colour, selected: selected)
                minZoom = area ? 0 : 2.5
            } else {
                view = badge(symbol: marker.symbol ?? category.symbol, tint: UIColor(category.tint), selected: selected)
                minZoom = 0
            }
            place(view, x: marker.x, y: marker.y, tag: .marker(marker), minZoom: minZoom)
            // A Fortress named like its area (Mirae General Hospital) already
            // has its name on the map
            let areaNames = Set(guide.markers.filter { $0.cat == "area" }.map { $0.name.resolved.lowercased() })
            if category.id == "fortress", let threat = marker.threat, !areaNames.contains(marker.name.resolved.lowercased()) {
                let name = label(marker.name.resolved, size: 10, weight: .bold, colour: UIColor(HajinThreat.color(threat)), selected: selected)
                name.isUserInteractionEnabled = false
                // Sits under the icon; offset in map points at the zoom it shows from
                place(name, x: marker.x, y: marker.y + 0.012, tag: .marker(marker), minZoom: 3)
            }
        }
        for pin in pins {
            let view = badge(symbol: "mappin", tint: UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
                             selected: selection == .pin(pin.id), pin: true)
            place(view, x: pin.x, y: pin.y, tag: .pin(pin.id), minZoom: 0)
        }
        rescaleOverlays()
    }

    private var tags: [ObjectIdentifier: HajinSelection] = [:]

    private func place(_ view: UIView, x: Double, y: Double, tag: HajinSelection, minZoom: CGFloat) {
        view.center = CGPoint(x: x * mapSize.width, y: y * mapSize.height)
        content.addSubview(view)
        overlays.append((view, minZoom))
        tags[ObjectIdentifier(view)] = tag
    }

    private func badge(symbol: String, tint: UIColor, selected: Bool, pin: Bool = false) -> UIView {
        let side: CGFloat = selected ? 34 : 26
        let view = UIView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.layer.cornerRadius = side / 2
        view.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.09, alpha: 0.92)
        view.layer.borderColor = tint.cgColor
        view.layer.borderWidth = selected ? 2.5 : 1.5
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.6
        view.layer.shadowRadius = 3
        view.layer.shadowOffset = .zero
        let config = UIImage.SymbolConfiguration(pointSize: side * 0.45, weight: .semibold)
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: config))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.frame = view.bounds
        view.addSubview(icon)
        if pin { view.backgroundColor = UIColor(red: 0.20, green: 0.16, blue: 0.02, alpha: 0.95) }
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight, colour: UIColor, selected: Bool) -> UIView {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: size, weight: weight)
        // Selected names go white and glow in their own colour, so the
        // selection never reads as a different threat level
        label.textColor = selected ? .white : colour
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.shadowColor = (selected ? colour : .black).cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = selected ? 5 : 2.5
        label.layer.shadowOffset = .zero
        let fitted = label.sizeThatFits(CGSize(width: 140, height: 60))
        label.frame = CGRect(origin: .zero, size: CGSize(width: fitted.width + 8, height: fitted.height + 6))
        return label
    }

    /// Markers keep their on-screen size whatever the zoom, and small place
    /// names only appear once there's room for them.
    private func rescaleOverlays() {
        let zoom = scrollView.zoomScale
        guard zoom > 0 else { return }
        let fit = max(scrollView.minimumZoomScale, 0.0001)
        let inverse = CGAffineTransform(scaleX: 1 / zoom, y: 1 / zoom)
        for overlay in overlays {
            overlay.view.transform = inverse
            overlay.view.isHidden = zoom / fit < overlay.minZoom
        }
    }

    // MARK: Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        // Nearest visible marker within a finger's reach, else deselect
        let point = gesture.location(in: content)
        let reach = 28 / scrollView.zoomScale
        var best: (HajinSelection, CGFloat)?
        for overlay in overlays where !overlay.view.isHidden {
            guard let tag = tags[ObjectIdentifier(overlay.view)] else { continue }
            let frame = overlay.view.frame.insetBy(dx: -reach / 2, dy: -reach / 2)
            guard frame.contains(point) else { continue }
            let distance = hypot(overlay.view.center.x - point.x, overlay.view.center.y - point.y)
            if best == nil || distance < best!.1 { best = (tag, distance) }
        }
        onSelect?(best?.0)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: content)
        let target = min(scrollView.zoomScale * 2, scrollView.maximumZoomScale)
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                   width: size.width, height: size.height), animated: true)
    }

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: content)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?(CGPoint(x: point.x / mapSize.width, y: point.y / mapSize.height))
    }

    // MARK: Zoom and centring

    func fly(to point: CGPoint) {
        guard bounds.width > 0, lastBounds != .zero else { pendingFocus = point; return }
        let target = max(scrollView.zoomScale, scrollView.minimumZoomScale * 4)
        UIView.animate(withDuration: 0.35) {
            self.scrollView.zoomScale = min(target, self.scrollView.maximumZoomScale)
            self.centre(on: point, animated: false)
        }
    }

    private func centre(on point: CGPoint, animated: Bool) {
        let zoom = scrollView.zoomScale
        var offset = CGPoint(x: point.x * mapSize.width * zoom - scrollView.bounds.width / 2,
                             y: point.y * mapSize.height * zoom - scrollView.bounds.height * 0.3)
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        offset.x = min(max(offset.x, 0), maxX)
        offset.y = min(max(offset.y, 0), maxY)
        scrollView.setContentOffset(offset, animated: animated)
    }

    /// Keeps the map centred when it's smaller than the screen.
    private func centreContent() {
        let x = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let y = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centreContent()
        rescaleOverlays()
    }
}
