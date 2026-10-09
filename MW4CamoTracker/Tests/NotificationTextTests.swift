import Testing
import Foundation
@testable import MW4CamoTracker

/// What the "new content" notification says: the manifest's words where it
/// has any, the built-in ones otherwise.
@Suite("Notification text")
struct NotificationTextTests {

    private func announcement(_ json: String) throws -> Manifest.Announcement {
        try JSONDecoder().decode(Manifest.Announcement.self, from: Data(json.utf8))
    }

    private var builtIn: (title: String, body: String) {
        BackgroundRefreshCoordinator.notificationText(catalogChanged: false, changedModes: ["multiplayer"], announcement: nil)
    }

    @Test func withoutAnAnnouncementTheBuiltInWordsStand() {
        #expect(builtIn.title == "mw4.notif.title".localized())
        #expect(builtIn.body.contains("mw4.mode.multiplayer".localized()))
    }

    @Test func theManifestCanSupplyBothLines() throws {
        let text = BackgroundRefreshCoordinator.notificationText(
            catalogChanged: true, changedModes: [],
            announcement: try announcement(#"{"title": {"en": "Season 1 is live"}, "body": {"en": "New weapons and camos to track."}}"#))
        #expect(text.title == "Season 1 is live")
        #expect(text.body == "New weapons and camos to track.")
    }

    @Test func aMissingLineFallsBackOnItsOwn() throws {
        let titleOnly = BackgroundRefreshCoordinator.notificationText(
            catalogChanged: false, changedModes: ["multiplayer"],
            announcement: try announcement(#"{"title": {"en": "Season 1 is live"}}"#))
        #expect(titleOnly.title == "Season 1 is live")
        #expect(titleOnly.body == builtIn.body)

        let bodyOnly = BackgroundRefreshCoordinator.notificationText(
            catalogChanged: false, changedModes: ["multiplayer"],
            announcement: try announcement(#"{"body": {"en": "Go and look."}}"#))
        #expect(bodyOnly.title == builtIn.title)
        #expect(bodyOnly.body == "Go and look.")
    }

    @Test func anEmptyLineCountsAsMissing() throws {
        let text = BackgroundRefreshCoordinator.notificationText(
            catalogChanged: false, changedModes: ["multiplayer"],
            announcement: try announcement(#"{"title": {"en": "  "}, "body": {"en": ""}}"#))
        #expect(text.title == builtIn.title)
        #expect(text.body == builtIn.body)
    }

    @Test func aManifestDecodesWithOrWithoutTheBlock() throws {
        let plain = #"{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}}"#
        #expect(try JSONDecoder().decode(Manifest.self, from: Data(plain.utf8)).notification == nil)
        let with = #"{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}, "notification": {"title": {"en": "Hello"}}}"#
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(with.utf8))
        #expect(manifest.notification?.title?.resolved() == "Hello")
        #expect(manifest.notification?.body == nil)
    }

    /// The live manifest has to keep decoding, with or without a message in it.
    @Test func theRepositorysOwnManifestShapeDecodes() throws {
        let live = #"{"catalog": {"version": "0.8.0", "path": "weapons.json"}, "modes": {"multiplayer": {"version": "0.7.0", "path": "multiplayer.json"}}}"#
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(live.utf8))
        #expect(manifest.modes["multiplayer"]?.version == "0.7.0")
    }

    @Test func anUpdateNotifiesUnlessTheManifestSaysSilent() throws {
        #expect(BackgroundRefreshCoordinator.shouldNotify(nil))
        #expect(BackgroundRefreshCoordinator.shouldNotify(try announcement(#"{"title": {"en": "Season 1"}}"#)))
        #expect(BackgroundRefreshCoordinator.shouldNotify(try announcement(#"{"silent": false}"#)))
        #expect(BackgroundRefreshCoordinator.shouldNotify(try announcement(#"{"silent": true}"#)) == false)
    }
}
