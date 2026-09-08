import Foundation
import SwiftUI
import UIKit

/// Builds mailto: links for data reports. There is no backend to wire up, so
/// email is the fastest way to get "this weapon's max level is wrong" style
/// reports in without building a whole feedback pipeline.
///
/// The point of pre-filling is that camo data is entered by hand from a game
/// that keeps changing: the weapon id, mode and current stored values are
/// exactly what is needed to fix a row without a round trip asking which
/// weapon, which mode, and what it currently says.
enum SupportMail {
    static let address = "support@camotracker.djr.li"

    /// The kinds of data problem worth a one-tap report. Raw values are the
    /// subject line suffix, so they stay readable in an inbox.
    enum Kind: String, CaseIterable, Identifiable {
        case maxLevel = "Wrong max level"
        case challenge = "Wrong challenge"
        case missingImage = "Missing or wrong image"
        case name = "Wrong name"
        case other = "Something else"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .maxLevel:     return "chevron.up.square"
            case .challenge:    return "checklist"
            case .missingImage: return "photo"
            case .name:         return "textformat"
            case .other:        return "ellipsis.circle"
            }
        }

        var labelKey: String {
            switch self {
            case .maxLevel:     return "mw4.ui.report.max_level"
            case .challenge:    return "mw4.ui.report.challenge"
            case .missingImage: return "mw4.ui.report.image"
            case .name:         return "mw4.ui.report.name"
            case .other:        return "mw4.ui.report.other"
            }
        }
    }

    /// General feedback, no item context.
    static func url(subject: String) -> URL? {
        url(subject: subject, body: diagnosticsFooter())
    }

    /// Pre-filled with everything needed to fix the row: which weapon, which
    /// mode, and what the app currently stores. Deliberately no URLs or host
    /// names, just the image filename.
    static func url(kind: Kind, weapon: WeaponEntry, mode: AppMode,
                    category: String? = nil, camo: ChallengeItem? = nil) -> URL? {
        var lines = [
            "Issue type: \(kind.rawValue)",
            "Weapon: \(weapon.name.resolved())",
            "Weapon ID: \(weapon.weaponId)",
            "Mode: \(mode.rawValue)",
        ]
        if let category { lines.append("Category: \(category)") }
        lines.append("Max level in app: \(weapon.maxLevel)")
        // Filename only. The full URL would put the CDN's host and directory
        // layout in every report, and the name alone is enough to find the asset.
        let imageName = weapon.imageURL.flatMap { URL(string: $0)?.lastPathComponent } ?? "none"
        lines.append("Image: \(imageName)")

        if let camo {
            lines.append("Camo: \(camo.name.resolved())")
            lines.append("Camo ID: \(camo.itemId)")
            if let requirement = camo.requirement {
                lines.append("Requirement in app: \(requirement.amount) \(requirement.unit)")
            }
        }
        return url(subject: "MW4 Camo Tracker: \(kind.rawValue)",
                   body: lines.joined(separator: "\n") + "\n\n" + diagnosticsFooter())
    }

    private static func diagnosticsFooter() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "---\nApp \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)"
    }

    private static func url(subject: String, body: String) -> URL? {
        let fullBody = "Describe the issue:\n\n\n" + body
        // & = + are legal in a query but would be read as mailto separators,
        // so they have to be encoded even though urlQueryAllowed permits them.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedBody = fullBody.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "mailto:\(address)?subject=\(encodedSubject)&body=\(encodedBody)")
    }
}

/// The "Report an issue" control on a weapon's page. A menu rather than a
/// single mailto so the subject line arrives already sorted by kind.
struct ReportIssueMenu: View {
    let weapon: WeaponEntry
    let mode: AppMode
    var category: String? = nil
    var camo: ChallengeItem? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(SupportMail.Kind.allCases) { kind in
                Button {
                    if let url = SupportMail.url(kind: kind, weapon: weapon, mode: mode,
                                                 category: category, camo: camo) {
                        openURL(url)
                    }
                } label: {
                    Label(kind.labelKey.localized(), systemImage: kind.symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 12, weight: .semibold))
                Text("mw4.ui.report.title".localized())
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Color.appInkMuted)
            .padding(12)
            .contentShape(Rectangle())
            .borderedCard()
        }
    }
}
