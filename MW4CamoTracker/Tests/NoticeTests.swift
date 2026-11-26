import Testing
import Foundation
@testable import MW4CamoTracker

@Suite("Notices")
struct NoticeTests {

    private func notices(_ json: String) throws -> [AppNotice] {
        try JSONDecoder().decode(NoticeFile.self, from: Data(json.utf8)).notices
    }

    private func day(_ string: String) -> Date {
        ChallengeItem.dayFormatter.date(from: string)!.addingTimeInterval(12 * 3600)
    }

    @Test func onlyAnIdAndATitleAreNeeded() throws {
        let list = try notices(#"{"notices":[{"id":"a","title":{"en":"Hello"}}]}"#)
        #expect(list.count == 1)
        #expect(list[0].isLive())
        #expect(list[0].link == nil)
        #expect(list[0].shares == false)
    }

    @Test func aBrokenNoticeIsLeftOutNotTheRest() throws {
        let list = try notices(#"{"notices":[{"id":"a"},7,{"id":"b","title":{"en":"Second"}},"x",{"id":"c","title":{"en":"Third"}}]}"#)
        #expect(list.map(\.id) == ["b", "c"])
    }

    @Test func switchedOffOrWithoutWordsIsNotShown() throws {
        let list = try notices(#"{"notices":[{"id":"off","enabled":false,"title":{"en":"Off"}},{"id":"blank","title":{"en":""}},{"id":"on","enabled":true,"title":{"en":"On"}}]}"#)
        #expect(AppNotice.current(in: list, dismissed: [])?.id == "on")
    }

    @Test func shownFromItsFirstDayToItsLastInclusive() throws {
        let notice = try notices(#"{"notices":[{"id":"a","title":{"en":"A"},"from":"2026-11-26","until":"2026-12-02"}]}"#)[0]
        #expect(notice.isLive(on: day("2026-11-25")) == false)
        #expect(notice.isLive(on: day("2026-11-26")))
        #expect(notice.isLive(on: day("2026-12-02")))
        #expect(notice.isLive(on: day("2026-12-03")) == false)
    }

    @Test func aDateThatIsNotADayHidesTheNotice() throws {
        let list = try notices(#"{"notices":[{"id":"a","title":{"en":"A"},"until":"2 Dec"},{"id":"b","title":{"en":"B"},"until":"2026-12-2"}]}"#)
        #expect(list.allSatisfy { !$0.isLive(on: day("2026-11-26")) })
    }

    @Test func aClosedNoticeGivesWayToTheNextAndANewIdAsksAgain() throws {
        let list = try notices(#"{"notices":[{"id":"a","title":{"en":"A"}},{"id":"b","title":{"en":"B"}}]}"#)
        #expect(AppNotice.current(in: list, dismissed: [])?.id == "a")
        #expect(AppNotice.current(in: list, dismissed: ["a"])?.id == "b")
        #expect(AppNotice.current(in: list, dismissed: ["a", "b"]) == nil)
        let renamed = try notices(#"{"notices":[{"id":"a-2","title":{"en":"A"}}]}"#)
        #expect(AppNotice.current(in: renamed, dismissed: ["a", "b"])?.id == "a-2")
    }

    @Test func onlyHttpsLinksGetAButton() throws {
        let list = try notices(#"{"notices":[{"id":"a","title":{"en":"A"},"url":"https://camo-track.app/android","action":"share"},{"id":"b","title":{"en":"B"},"url":"http://camo-track.app"},{"id":"c","title":{"en":"C"},"url":"tel:999"},{"id":"d","title":{"en":"D"},"url":"not a link"}]}"#)
        #expect(list[0].link?.absoluteString == "https://camo-track.app/android")
        #expect(list[0].shares)
        #expect(list[1].link == nil)
        #expect(list[2].link == nil)
        #expect(list[3].link == nil)
    }

    @Test @MainActor func closingIsRememberedAcrossLaunches() throws {
        let name = "NoticeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"notices":[{"id":"a","title":{"en":"A"}}]}"#.utf8).write(to: dir.appendingPathComponent("notices.json"))

        let first = NoticeStore(defaults: defaults, cacheDir: dir)
        let shown = try #require(first.current)
        first.dismiss(shown)
        #expect(first.current == nil)
        #expect(NoticeStore(defaults: defaults, cacheDir: dir).current == nil)
    }
}
