import XCTest

/// On an iPad the lists become grids, two or three cards to a List row. A
/// List likes to treat a row as one button, so these make sure a tap on a
/// card opens that card and nothing else. Run on an iPad simulator; on a
/// phone the same taps go through the ordinary one-card rows.
final class GridTapUITests: XCTestCase {

    private func launch(category: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // The screenshot harness: straight to a tab, no splash or onboarding.
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        if let category { app.launchEnvironment["SS_CAT"] = "\(category)" }
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
        return app
    }

    func testTappingAWeaponCardOpensThatWeaponOnly() {
        let app = launch(category: 0) // Assault Rifles
        let second = app.staticTexts["M4"]
        XCTAssertTrue(second.waitForExistence(timeout: 15))

        // The second card in the first row, the one a row-wide tap would miss.
        second.tap()
        XCTAssertTrue(app.staticTexts["Weapon Level"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["M4"].exists)

        // One back returns to the list: nothing else was pushed with it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Assault Rifles"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weapon Level"].exists)

        app.staticTexts["HAN 86"].tap()
        XCTAssertTrue(app.navigationBars["HAN 86"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weapon Level"].exists)
    }

    func testTappingACategoryCardOpensThatCategoryOnly() {
        let app = launch()
        let second = app.staticTexts["SMGs"]
        XCTAssertTrue(second.waitForExistence(timeout: 15))
        second.tap()
        XCTAssertTrue(app.navigationBars["SMGs"].waitForExistence(timeout: 5))

        // One back lands on the tab root, so only one screen was pushed.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Multiplayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assault Rifles"].exists)
    }
}
