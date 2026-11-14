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
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>", "-mw4_home_class", "-1"]
        app.launch()
        return app
    }

    func testTappingAWeaponCardOpensThatWeaponOnly() {
        let app = launch(category: 0) // Assault Rifles
        let second = app.staticTexts["M4"]
        XCTAssertTrue(second.waitForExistence(timeout: 15))

        // The second card in the first row, the one a row-wide tap would miss.
        // (MW4 counts a weapon's unlocks rather than its level.)
        second.tap()
        XCTAssertTrue(app.staticTexts["Weapon Unlocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["M4"].exists)

        // One back returns to the list: nothing else was pushed with it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Assault Rifles"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weapon Unlocks"].exists)

        app.staticTexts["HAN 86"].tap()
        XCTAssertTrue(app.navigationBars["HAN 86"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weapon Unlocks"].exists)
    }

    /// The class chips above the weapons filter the one list in place:
    /// SMGs shows the SMGs and nothing else, All brings every weapon back.
    func testClassChipsFilterTheList() {
        let app = launch()
        let smgs = app.buttons["classChip.1"]
        XCTAssertTrue(smgs.waitForExistence(timeout: 15))
        for _ in 0..<4 where !smgs.isHittable { app.swipeUp() }
        smgs.tap()
        XCTAssertTrue(app.staticTexts["ISO Nightshade"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Rezi 12"].exists)

        // Assault Rifles lead the full list, just under the chips
        app.buttons["classChip.-1"].tap()
        XCTAssertTrue(app.staticTexts["Hyeon Burst"].waitForExistence(timeout: 5))
    }

    /// Customise: switching Suggested off takes it off the tab, and Reset
    /// brings it back (which also leaves the layout clean for other tests).
    /// The layout is Premium's, so this runs as a Premium player.
    func testCustomiseHidesASection() {
        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchEnvironment["MW4_PREMIUM"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>", "-mw4_home_class", "-1"]
        app.launch()

        // Below the layout list and the locked-challenges switch: lift the
        // sheet to its full height first.
        func reset() {
            let button = app.buttons["Reset to default"]
            for _ in 0..<3 where !button.isHittable { app.swipeUp() }
            button.tap()
        }

        func customise(_ change: () -> Void) {
            XCTAssertTrue(app.buttons["customiseHome"].waitForExistence(timeout: 15))
            app.buttons["customiseHome"].tap()
            // Modes and Language come first, so the layout switches can
            // start below the fold: wait for the sheet itself.
            XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
            change()
            app.navigationBars.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Weapons"].waitForExistence(timeout: 5))
        }

        customise(reset)
        XCTAssertTrue(app.staticTexts["Suggested"].exists)

        customise {
            // Under Modes and Language now: lift the sheet until it shows.
            let suggested = app.switches["Suggested"]
            for _ in 0..<4 where !(suggested.exists && suggested.isHittable) { app.swipeUp() }
            // Once the list has stopped: a tap while it's still gliding
            // only stops it. Then the switch itself, which on an iPad is
            // narrower than the row's element.
            sleep(2)
            suggested.switches.firstMatch.tap()
        }
        XCTAssertFalse(app.staticTexts["Suggested"].exists)

        customise(reset)
        XCTAssertTrue(app.staticTexts["Suggested"].exists)
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
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(hex)>", "-mw4_home_class", "-1"]
        app.launch()
        return app
    }

    /// Tapping anywhere on a tick-box camo's card ticks it: here a Military
    /// camo, whose tick sets the weapon's unlocks to it.
    func testTappingATickBoxCardCompletesIt() {
        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["SS_WEAPON"] = "1" // M4, max 72
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-mw4_progress_v2", "<\(Self.emptySave)>", "-mw4_home_class", "-1"]
        app.launch()

        let detail = app.staticTexts["Needs 9 weapon unlocks."]
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        detail.tap()
        XCTAssertTrue(app.staticTexts["Earned at 9 weapon unlocks."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["9/71"].exists)
    }

    /// A camo with a counter isn't completed by a tap on its card, but its
    /// + still counts one up.
    func testTappingACounterCardLeavesItAlone() {
        let app = launchWithPlatinumOpen()
        // The weapon page's own tabs, buttons rather than a system segmented control
        let tab = app.buttons["Completionist"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()

        let count = app.descendants(matching: .any)["0/50"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        app.staticTexts["Get 50 Headshots against Players"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["0/50"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["50/50"].exists)

        // Plus sits just right of the count.
        count.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 18, dy: 0)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["1/50"].waitForExistence(timeout: 5))

        // The tick box still completes it in one tap, no typing 50. A done
        // camo drops its counter. The camo is one element (for VoiceOver),
        // so the tick is tapped where it sits, at the card's leading edge.
        app.buttons["tick.Platinum"].coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 12, dy: 0)).tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: app.descendants(matching: .any)["1/50"])
        wait(for: [gone], timeout: 5)
    }

    /// A ticked camo says when it was unlocked, and the weapon's share
    /// button opens its card.
    func testTickedCamoShowsItsDateAndTheWeaponShares() {
        // M4 at max level: its Military camos are earned, the Specials open
        let save = Data(#"{"weaponLevels":{"1":72},"weaponPrestige":{},"amounts":{},"completed":[]}"#.utf8)
            .map { String(format: "%02x", $0) }.joined()
        let app = XCUIApplication()
        app.launchEnvironment["SS_SCREEN"] = "multiplayer"
        app.launchEnvironment["SS_WEAPON"] = "1"
        app.launchEnvironment["MW4_OFFLINE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB", "-mw4_progress_v2", "<\(save)>",
                                "-mw4_home_class", "-1", "-mw4_quick_tick", "YES"]
        app.launch()

        let smoke = app.descendants(matching: .any)["tick.Smoke"]
        XCTAssertTrue(smoke.waitForExistence(timeout: 15))
        smoke.tap()
        app.descendants(matching: .any)["tick.Stormwave"].tap()
        let today = Date.now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
        let stamp = NSPredicate(format: "value CONTAINS %@", "Unlocked \(today)")
        XCTAssertTrue(app.descendants(matching: .any).matching(stamp).firstMatch.waitForExistence(timeout: 5))
        add(XCTAttachment(screenshot: app.screenshot()))

        app.buttons["weapon.share"].tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
