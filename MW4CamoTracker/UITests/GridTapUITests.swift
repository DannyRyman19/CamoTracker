import XCTest

/// On an iPad the lists become grids, two or three cards to a List row. A
/// List likes to treat a row as one button, so these make sure a tap on a
/// card opens that card and nothing else. Run on an iPad simulator; on a
/// phone the same taps go through the ordinary one-card rows.
final class GridTapUITests: XCTestCase {

    /// An empty save, whatever earlier tests left behind (as hex for the
    /// arguments domain).
    private static let emptySave = Data(#"{"weaponLevels":{},"weaponPrestige":{},"amounts":{},"completed":[]}"#.utf8)
        .map { String(format: "%02x", $0) }.joined()

    private func launch(category: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // The screenshot harness: straight to a tab, no splash or onboarding.
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        if let category { app.launchEnvironment["SS_CAT"] = "\(category)" }
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>"]
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

    /// "See all" in the Weapons header opens every weapon in one list, and
    /// no "All weapons" card sits among the classes any more.
    func testSeeAllOpensEveryWeapon() {
        let app = launch()
        let link = app.buttons["seeAllWeapons"]
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["All weapons"].exists)
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.navigationBars["All weapons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HAN 86"].exists)
    }

    /// Customise: switching Suggested off takes it off the tab, and Reset
    /// brings it back (which also leaves the layout clean for other tests).
    func testCustomiseHidesASection() {
        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>"]
        app.launch()

        func customise(_ change: () -> Void) {
            XCTAssertTrue(app.buttons["customiseHome"].waitForExistence(timeout: 15))
            app.buttons["customiseHome"].tap()
            XCTAssertTrue(app.switches["Suggested"].waitForExistence(timeout: 5))
            change()
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Weapons"].waitForExistence(timeout: 5))
        }

        customise { app.buttons["Reset to default"].tap() }
        XCTAssertTrue(app.staticTexts["Suggested"].exists)

        customise {
            app.switches["Suggested"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertFalse(app.staticTexts["Suggested"].exists)

        customise { app.buttons["Reset to default"].tap() }
        XCTAssertTrue(app.staticTexts["Suggested"].exists)
    }

    func testTappingACategoryCardOpensThatCategoryOnly() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Weapons"].waitForExistence(timeout: 15))
        // Below Suggested and the filter row: scroll it into view.
        let second = app.staticTexts["SMGs"]
        for _ in 0..<4 where !second.isHittable { app.swipeUp() }
        second.tap()
        XCTAssertTrue(app.navigationBars["SMGs"].waitForExistence(timeout: 5))

        // One back lands on the tab root, so only one screen was pushed.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Multiplayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Assault Rifles"].exists)
    }

    /// A save where every Assault Rifle has Gold, so HAN 86's Platinum
    /// (a 50-headshot counter) is open, passed in through the arguments
    /// domain so the test needs no setup screens.
    private func launchWithPlatinumOpen() -> XCUIApplication {
        let rifles = [0, 1, 2, 3, 4, 19, 20, 21]
        var amounts: [String: Int] = [:]
        for weapon in rifles { amounts["comp|multiplayer|\(weapon)|0"] = 1 }
        // The HAN 86's Specials are counters (20, 50 and 15).
        for (item, amount) in [8: 20, 9: 50, 10: 15] { amounts["camo|multiplayer|0|\(item)"] = amount }
        let completed = rifles.flatMap { weapon in (8...10).map { "camo|multiplayer|\(weapon)|\($0)" } }
        let store: [String: Any] = [
            "weaponLevels": Dictionary(uniqueKeysWithValues: rifles.map { ("\($0)", 72) }),
            "weaponPrestige": [String: Int](),
            "amounts": amounts,
            "completed": completed,
        ]
        let json = try! JSONSerialization.data(withJSONObject: store)
        let hex = json.map { String(format: "%02x", $0) }.joined()

        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["SS_WEAPON"] = "0" // HAN 86
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(hex)>"]
        app.launch()
        return app
    }

    /// Tapping anywhere on a tick-box camo's card ticks it: here a Military
    /// camo, whose tick sets the weapon level to it.
    func testTappingATickBoxCardCompletesIt() {
        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["SS_WEAPON"] = "1" // M4, max 72
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>"]
        app.launch()

        let detail = app.staticTexts["Unlocks at weapon level 10."]
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        detail.tap()
        XCTAssertTrue(app.staticTexts["Earned at weapon level 10."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["10/72"].exists)
    }

    /// A camo with a counter isn't completed by a tap on its card, but its
    /// + still counts one up.
    func testTappingACounterCardLeavesItAlone() {
        let app = launchWithPlatinumOpen()
        let tab = app.segmentedControls.buttons["Completionist"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()

        let count = app.descendants(matching: .any)["0/50"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        app.staticTexts["Get 50 headshot kills against players."].tap()
        XCTAssertTrue(app.descendants(matching: .any)["0/50"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["50/50"].exists)

        // Plus sits just right of the count.
        count.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 18, dy: 0)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["1/50"].waitForExistence(timeout: 5))

        // The tick box still completes it in one tap, no typing 50.
        let name = app.staticTexts["Platinum"]
        name.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 1)).withOffset(CGVector(dx: -22, dy: 0)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["50/50"].waitForExistence(timeout: 5))
    }
}
