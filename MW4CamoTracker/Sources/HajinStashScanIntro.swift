import PhotosUI
import SwiftUI

/// What "Read a stash photo" does, before the photo picker: a looping
/// demo (a scan line sweeps a little stash and the totals fill in), tips for
/// a good photo, and the Choose a photo button.
@available(iOS 17.0, *)
struct HajinStashScanIntro: View {
    @Binding var pick: PhotosPickerItem?
    /// A photo taken with the camera instead of picked
    @Binding var captured: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var showsCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HajinStashScanDemo()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    Text("mw4.ui.hajin.grid_intro".localized())
                        .font(.subheadline)
                        .foregroundStyle(Color.appInk)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("mw4.ui.hajin.grid_tips_title".localized().uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.8)
                            .foregroundStyle(Color.appInkMuted)
                        tip("camera.viewfinder", "mw4.ui.hajin.grid_tip_straight")
                        tip("photo.on.rectangle", "mw4.ui.hajin.grid_tip_screenshot")
                        tip("square.grid.3x3", "mw4.ui.hajin.grid_tip_tab")
                        tip("sun.max", "mw4.ui.hajin.grid_tip_glare")
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.appSurface))
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showsCamera = true } label: {
                            Label("mw4.ui.hajin.grid_camera".localized(), systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundStyle(Color.black.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentDMZ))
                        }
                        .buttonStyle(.plain)
                    }
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("mw4.ui.hajin.grid_choose".localized(), systemImage: "photo.stack")
                            .font(.headline)
                            .foregroundStyle(Color.appInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentDMZ, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("mw4.ui.hajin.grid_scan".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $showsCamera) {
            HajinCamera { image in captured = image }
                .ignoresSafeArea()
        }
    }

    private func tip(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
                .frame(width: 22)
            Text(key.localized())
                .font(.subheadline)
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The system camera, for a photo of the stash taken there and then.
struct HajinCamera: UIViewControllerRepresentable {
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: HajinCamera
        init(_ parent: HajinCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.done(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// The demo: a little 3 x 3 stash with stack counts; a scan line sweeps down,
/// each row lights up as it's read, and the totals on the right count up.
/// Loops every few seconds. Built from the guide's own item pictures.
struct HajinStashScanDemo: View {
    @EnvironmentObject private var store: HajinStore

    private struct Stack { let id: String; let count: Int }
    private let grid: [[Stack]] = [
        [Stack(id: "rigid-synthetics", count: 10), Stack(id: "rigid-synthetics", count: 10), Stack(id: "rigid-synthetics", count: 9)],
        [Stack(id: "biomaterials", count: 10), Stack(id: "biomaterials", count: 3), Stack(id: "detonators", count: 10)],
        [Stack(id: "reactive-metals", count: 10), Stack(id: "reactive-metals", count: 2), Stack(id: "cpu", count: 6)],
    ]
    private static let cycle = 6.0
    private static let sweep = 3.0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            // 0...1 while sweeping, then held at 1 while the totals rest
            let progress = min(1, max(0, (t - 0.4) / Self.sweep))
            let fade = t > Self.cycle - 0.5 ? (Self.cycle - t) / 0.5 : 1
            HStack(alignment: .center, spacing: 16) {
                stash(progress)
                totals(progress)
                    .frame(width: 150, alignment: .leading)
            }
            .opacity(fade)
        }
        .frame(height: 190)
        .accessibilityLabel("mw4.ui.hajin.grid_intro".localized())
    }

    private func stash(_ progress: Double) -> some View {
        let tile: CGFloat = 52, gap: CGFloat = 6
        let height = tile * 3 + gap * 2
        return ZStack(alignment: .top) {
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { c in
                            let stack = grid[r][c]
                            let read = progress * 3 > Double(r) + 0.5
                            ZStack(alignment: .topTrailing) {
                                HajinItemTile(item: store.guide?.item(stack.id), size: tile)
                                Text("\(stack.count)")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 1)
                                    .padding(3)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentDMZ, lineWidth: read ? 2 : 0))
                            .scaleEffect(read ? 1 : 0.96)
                            .animation(.spring(duration: 0.3), value: read)
                        }
                    }
                }
            }
            // the scan line
            if progress > 0 && progress < 1 {
                LinearGradient(colors: [Color.accentDMZ.opacity(0), Color.accentDMZ.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.accentDMZ).frame(height: 2) }
                    .offset(y: height * progress - 26)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: tile * 3 + gap * 2, height: height, alignment: .top)
        .clipped()
    }

    /// Each item's total, counting up as its stacks are read.
    private func totals(_ progress: Double) -> some View {
        var order: [String] = []
        for row in grid { for s in row where !order.contains(s.id) { order.append(s.id) } }
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(order, id: \.self) { id in
                let soFar = grid.enumerated().reduce(0) { sum, row in
                    let rowRead = min(1, max(0, progress * 3 - Double(row.offset)))
                    return sum + row.element.filter { $0.id == id }.reduce(0) { $0 + Int((Double($1.count) * rowRead).rounded()) }
                }
                HStack(spacing: 6) {
                    HajinItemTile(item: store.guide?.item(id), size: 20)
                    Text(store.guide?.item(id)?.name.resolved ?? id)
                        .font(.caption)
                        .foregroundStyle(Color.appInk)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(soFar)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(soFar > 0 ? Color.accentDMZ : Color.appInkMuted)
                        .contentTransition(.numericText())
                }
                .opacity(soFar > 0 ? 1 : 0.35)
            }
        }
    }
}
