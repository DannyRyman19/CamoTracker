import CoreImage.CIFilterBuiltins
import SwiftUI

/// Progress and milestone cards to share: a picture of where the player is,
/// with the App Store link on it as a QR code and in the message beside it,
/// so every share is also a way in for whoever sees it.
enum ShareCard {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6775247927")!
    /// 4:5, the shape Instagram, X and Messages all show whole.
    static let size = CGSize(width: 360, height: 450)

    /// The card drawn at 3x: 1080 x 1350.
    @MainActor
    static func render<V: View>(_ card: V) -> UIImage? {
        let renderer = ImageRenderer(content: card
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// The message that goes with the picture, ending in the link.
    static func message(_ line: String) -> String {
        line + "\n" + String(format: "mw4.ui.share.tracked_with".localized(), appStoreURL.absoluteString)
    }

    /// The App Store link as a QR code, square and sharp at any size.
    static let qrCode: UIImage? = {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(appStoreURL.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }()

    // MARK: Progress

    /// Everything the progress card shows, read from the trackers up front
    /// so the card itself is plain values (`ImageRenderer` draws it outside
    /// the app's environment).
    struct Progress {
        struct Camo { let name: String; let gradient: [Color]; let done: Int; let total: Int }
        struct Mode { let name: String; let symbol: String; let accent: Color; let fraction: Double; let tiers: [(name: String, gradient: [Color], achieved: Bool)] }
        let overall: Double
        let completionist: [Camo]
        let modes: [Mode]
        let dmz: [DMZStatLine]
        let cash: Int

        @MainActor
        init(viewModel: TrackerViewModel, hajin: HajinStore) {
            let visible = viewModel.visibleModes
            modes = visible.map { mode in
                let tiers = mode.masteryCamos
                return Mode(name: mode.displayNameKey.localized(), symbol: mode.symbol, accent: mode.accent,
                            fraction: viewModel.trueCompletionFraction(mode: mode.rawValue),
                            tiers: [tiers.tier1, tiers.tier2, tiers.tier3].enumerated().map { index, camo in
                                (camo.name, camo.gradient, viewModel.isMasteryAchieved(mode: mode.rawValue, tier: index + 1))
                            })
            }
            overall = modes.isEmpty ? 0 : modes.map(\.fraction).reduce(0, +) / Double(modes.count)
            // Camos are one track per weapon, read from the first mode as Stats does
            let first = visible.first ?? .multiplayer
            let total = viewModel.totalWeaponCount
            completionist = first.completionistCamos.enumerated().map { index, camo in
                Camo(name: camo.name, gradient: camo.gradient,
                     done: viewModel.completionistCount(mode: first.rawValue, step: index), total: total)
            }
            let showsDMZ = visible.contains(.dmz) && hajin.guide != nil
            dmz = showsDMZ ? hajin.statLines : []
            cash = showsDMZ ? hajin.cash : 0
        }
    }

    static func progressMessage(_ data: Progress) -> String {
        message(String(format: "mw4.ui.share.progress_line".localized(), Int(data.overall * 100)))
    }

    // MARK: Milestone

    /// The milestone card for a banner, with its weapon's picture when it
    /// has one (fetched first: the renderer can't wait on a download).
    @MainActor
    static func milestoneImage(_ banner: MilestoneBanner, viewModel: TrackerViewModel) async -> UIImage? {
        let weapon = banner.weaponId.flatMap(viewModel.weapon(id:))
        var picture: UIImage?
        if let url = weapon?.imageURL.flatMap(URL.init(string:)) {
            picture = await ImageStore.shared.image(for: url)
        }
        return render(MilestoneCardView(banner: banner, weaponName: weapon?.name.resolved(), picture: picture))
    }

    @MainActor
    static func milestoneMessage(_ banner: MilestoneBanner, viewModel: TrackerViewModel) -> String {
        if let name = banner.weaponId.flatMap(viewModel.weapon(id:))?.name.resolved() {
            return message(String(format: "mw4.ui.share.milestone_weapon".localized(), banner.title, name))
        }
        return message("\(banner.title). \(banner.subtitle)")
    }
}

// MARK: - Cards

/// The app's mark and name across the top of a card.
private struct CardHeader: View {
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image("AppIcon-Preview")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Camo Track")
                .font(.hitmarker(15))
                .foregroundStyle(Color.appInk)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}

/// The QR code and where it goes, along the foot of a card.
private struct CardFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            if let qr = ShareCard.qrCode {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("mw4.ui.share.footer_title".localized())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text("mw4.ui.share.footer_subtitle".localized())
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.appInkMuted)
            }
            Spacer()
        }
    }
}

/// Text painted in a camo's colors, held still (the app's shimmer is an
/// animation, and a card is one frame).
private struct CamoText: View {
    let text: String
    let gradient: [Color]
    var font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(LinearGradient(colors: gradient.count > 1 ? gradient : [gradient.first ?? .appInk, gradient.first ?? .appInk],
                                            startPoint: .leading, endPoint: .trailing))
            .shadow(color: (gradient.first ?? .clear).opacity(0.5), radius: 5)
    }
}

/// A completion ring without the app ring's animation.
private struct StillRing: View {
    let fraction: Double
    let accent: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.appSurface2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(fraction >= 1 ? AnyShapeStyle(AngularGradient(colors: .gold + [.camoGold], center: .center))
                                      : AnyShapeStyle(accent),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction > 0 ? 1 : 0)
        }
    }
}

private struct CardBackground: View {
    let glow: Color

    var body: some View {
        ZStack {
            Color.appBackground
            RadialGradient(colors: [glow.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 320)
        }
    }
}

struct ProgressCardView: View {
    let data: ShareCard.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(trailing: Date.now.formatted(date: .abbreviated, time: .omitted))

            HStack(spacing: 16) {
                ZStack {
                    StillRing(fraction: data.overall, accent: .camoGold, lineWidth: 9)
                    Text("\(min(Int(data.overall * 100), 100))%")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.appInk)
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(data.modes, id: \.name) { mode in
                        HStack(spacing: 6) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(mode.accent)
                                .frame(width: 14)
                            Text(mode.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.appInk)
                            Spacer(minLength: 4)
                            HStack(spacing: 2) {
                                ForEach(mode.tiers.indices, id: \.self) { i in
                                    Image(systemName: mode.tiers[i].achieved ? "diamond.fill" : "diamond")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(mode.tiers[i].achieved ? (mode.tiers[i].gradient.first ?? mode.accent)
                                                                                : Color.appInkMuted.opacity(0.5))
                                }
                            }
                            Text("\(Int(mode.fraction * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(mode.accent)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(data.completionist, id: \.name) { camo in
                    VStack(spacing: 3) {
                        CamoText(text: camo.name, gradient: camo.gradient, font: .hitmarker(11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(camo.done)/\(camo.total)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(camo.done > 0 ? Color.appInk : Color.appInkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.appSurface))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder((camo.gradient.first ?? .appInkMuted).opacity(camo.done > 0 ? 0.55 : 0.15), lineWidth: 1))
                }
            }

            if !data.dmz.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("mw4.ui.stats.dmz".localized(), systemImage: AppMode.dmz.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.accentDMZ)
                        Spacer()
                        if data.cash > 0 {
                            Text("$\(data.cash.formatted())")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.appInkMuted)
                        }
                    }
                    ForEach(data.dmz) { line in
                        HStack(spacing: 8) {
                            Text(line.title)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.appInk)
                                .frame(width: 150, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            ProgressBar(fraction: line.fraction, accent: .accentDMZ)
                            Text("\(line.done)/\(line.total)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.appInkMuted)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.appSurface))
            }

            Spacer(minLength: 0)
            CardFooter()
        }
        .padding(20)
        .background(CardBackground(glow: data.modes.first?.accent ?? .accentMultiplayer))
    }
}

struct MilestoneCardView: View {
    let banner: MilestoneBanner
    let weaponName: String?
    let picture: UIImage?

    private var main: Color { banner.titleGradient.first ?? .camoGold }

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(trailing: Date.now.formatted(date: .abbreviated, time: .omitted))
            Spacer(minLength: 0)
            Group {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 140)
                        .shadow(color: main.opacity(0.55), radius: 18)
                } else {
                    Image(systemName: banner.icon)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: banner.titleGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: main.opacity(0.55), radius: 18)
                }
            }
            .frame(height: 150)
            Spacer(minLength: 0)
            CamoText(text: banner.title, gradient: banner.titleGradient, font: .hitmarker(30))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(weaponName ?? banner.subtitle)
                .font(weaponName == nil ? .system(size: 14) : .hitmarker(20))
                .foregroundStyle(weaponName == nil ? Color.appInkMuted : Color.appInk)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 10)
            Spacer(minLength: 0)
            CardFooter()
        }
        .padding(20)
        .background(CardBackground(glow: main))
        .overlay(Rectangle().strokeBorder(LinearGradient(colors: banner.titleGradient, startPoint: .topLeading,
                                                         endPoint: .bottomTrailing).opacity(0.5), lineWidth: 3))
    }
}

// MARK: - Preview sheet

/// The card as it will be sent, with the share button under it.
struct ShareCardSheet: View {
    let image: UIImage?
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                        .frame(maxWidth: 420)
                    ShareLink(item: Image(uiImage: image), message: Text(message),
                              preview: SharePreview("Camo Track", image: Image(uiImage: image))) {
                        Label("mw4.ui.share.button".localized(), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: 420)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.camoGold))
                            .foregroundStyle(Color.appBackground)
                    }
                } else {
                    ProgressView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("mw4.ui.share.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.done".localized()) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A milestone's card, drawn once its weapon picture is in.
struct MilestoneShareSheet: View {
    let banner: MilestoneBanner
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var image: UIImage?

    var body: some View {
        ShareCardSheet(image: image, message: ShareCard.milestoneMessage(banner, viewModel: viewModel))
            .task { image = await ShareCard.milestoneImage(banner, viewModel: viewModel) }
    }
}

/// The progress card, from Stats.
struct ProgressShareSheet: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @EnvironmentObject private var hajin: HajinStore
    @State private var image: UIImage?
    @State private var message = ""

    var body: some View {
        ShareCardSheet(image: image, message: message)
            .task {
                let data = ShareCard.Progress(viewModel: viewModel, hajin: hajin)
                message = ShareCard.progressMessage(data)
                image = ShareCard.render(ProgressCardView(data: data))
            }
    }
}
