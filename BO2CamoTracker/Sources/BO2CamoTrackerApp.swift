import SwiftUI

@main
struct BO2CamoTrackerApp: App {
    @State private var viewModel = TrackerViewModel()

    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
    }

    private func configureAppearance() {
        let bold = UIFont(name: "AgencyFB-Bold", size: 36) ?? UIFont.boldSystemFont(ofSize: 36)
        let boldSmall = UIFont(name: "AgencyFB-Bold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18)
        let reg = UIFont(name: "AgencyFB-Reg", size: 17) ?? UIFont.systemFont(ofSize: 17)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [
            .font: bold,
            .foregroundColor: UIColor.white
        ]
        appearance.titleTextAttributes = [
            .font: boldSmall,
            .foregroundColor: UIColor.white
        ]
        appearance.buttonAppearance.normal.titleTextAttributes = [.font: reg]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Tab bar labels
        let tabReg = UIFont(name: "AgencyFB-Reg", size: 10) ?? UIFont.systemFont(ofSize: 10)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabReg], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabReg], for: .selected)
    }
}
