import MessageUI
import SwiftUI
import UIKit

/// What one stash photo read saw, for "Send this photo": the photo and the
/// reader's working (where it guessed the grid, where the player put it,
/// every tile's answer), so a misread can be replayed on the Mac and the
/// player's corrections used as the right answers.
struct HajinScanReport {
    let image: UIImage
    let quality: [HajinPhotoQuality]
    let guessedCorners: [CGPoint]?
    let corners: [CGPoint]
    let moved: Bool
    let tiles: [HajinStashGrid.Tile]
    let found: [String: Int]
    let unsure: Set<String>
    let sureness: [String: Float]
    let cash: Int?
    let level: Int?

    /// The photo, at most 2400 px on its long side.
    func photoData() -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2400 / max(longest, 1))
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.85) }
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.85)
    }

    /// The reader's working plus what the player had and changed in the review.
    @MainActor func json(had: [String: Int], edited: [String: Int], skipped: Set<String>) -> Data? {
        func points(_ p: [CGPoint]?) -> [[Double]]? { p?.map { [($0.x * 10_000).rounded() / 10_000, ($0.y * 10_000).rounded() / 10_000] } }
        var device = utsname()
        uname(&device)
        let model = withUnsafeBytes(of: &device.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let info = Bundle.main.infoDictionary
        let report: [String: Any?] = [
            "app": "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "ios": UIDevice.current.systemVersion,
            "device": model,
            "photo": [Int(image.size.width), Int(image.size.height)],
            "quality": quality.map(\.rawValue),
            "guessedCorners": points(guessedCorners),
            "corners": points(corners),
            "movedByPlayer": moved,
            "tiles": tiles.map { t -> [String: Any] in
                var d: [String: Any] = ["r": t.row, "c": t.column, "id": t.id, "conf": (Double(t.confidence) * 1000).rounded() / 1000]
                if let n = t.count { d["count"] = n }
                return d
            },
            "found": found,
            "unsure": unsure.sorted(),
            "sureness": sureness.mapValues { (Double($0) * 1000).rounded() / 1000 },
            "cash": cash,
            "level": level,
            "had": had,
            "editedByPlayer": edited,
            "skippedByPlayer": skipped.sorted(),
        ]
        return try? JSONSerialization.data(withJSONObject: report.compactMapValues { $0 }, options: [.prettyPrinted, .sortedKeys])
    }
}

/// "Send this photo to improve the reader": the photo and the report by
/// email (Mail when it's set up, the share sheet otherwise). Nothing leaves
/// the phone unless the player sends it.
struct HajinSendScanButton: View {
    let report: HajinScanReport
    /// The review's state at the moment of sending: what the stash had, and
    /// the player's corrections
    let review: () -> (had: [String: Int], edited: [String: Int], skipped: Set<String>)
    @State private var mail: HajinMailDraft?
    @State private var share: [Any]?

    var body: some View {
        Button(action: send) {
            Label("mw4.ui.hajin.send_scan".localized(), systemImage: "paperplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
        }
        .sheet(item: $mail) { draft in HajinMailView(draft: draft).ignoresSafeArea() }
        .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) {
            if let share { HajinShareSheet(items: share) }
        }
    }

    private func send() {
        let state = review()
        guard let photo = report.photoData(), let json = report.json(had: state.had, edited: state.edited, skipped: state.skipped) else { return }
        let subject = "Camo Tracker: stash reader report"
        let body = "mw4.ui.hajin.send_scan_body".localized()
        if MFMailComposeViewController.canSendMail() {
            mail = HajinMailDraft(subject: subject, body: body, attachments: [
                (photo, "image/jpeg", "stash.jpg"), (json, "application/json", "stash-report.json"),
            ])
        } else {
            // No Mail account: hand the two files to the share sheet with the address
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stash-report-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let photoURL = dir.appendingPathComponent("stash.jpg"), jsonURL = dir.appendingPathComponent("stash-report.json")
            try? photo.write(to: photoURL)
            try? json.write(to: jsonURL)
            share = [String(format: "mw4.ui.hajin.send_scan_share".localized(), SupportMail.address), photoURL, jsonURL]
        }
    }
}

struct HajinMailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let attachments: [(data: Data, mime: String, name: String)]
}

struct HajinMailView: UIViewControllerRepresentable {
    let draft: HajinMailDraft
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([SupportMail.address])
        mail.setSubject(draft.subject)
        mail.setMessageBody(draft.body, isHTML: false)
        for a in draft.attachments { mail.addAttachmentData(a.data, mimeType: a.mime, fileName: a.name) }
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    @MainActor final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

struct HajinShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
