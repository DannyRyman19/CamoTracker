import SwiftUI

extension String {
    /// Looks up display text in the bundled `Localizable.strings` — nameKeys from
    /// the network JSON are never rendered directly, so translations ship with
    /// the app instead of duplicating whole data files per locale.
    func localized() -> String {
        NSLocalizedString(self, bundle: .main, comment: "")
    }
}

struct ProgressBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appSurface2)
                Capsule().fill(accent).frame(width: max(0, geo.size.width * min(fraction, 1)))
            }
        }
        .frame(height: 4)
    }
}
