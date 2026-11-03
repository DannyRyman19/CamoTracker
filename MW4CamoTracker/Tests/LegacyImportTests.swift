import Foundation
import Testing
@testable import MW4CamoTracker

/// The BO6 and BO7 apps' exports share weapon names (the Knife), so each
/// game takes only its own old app's file.
struct LegacyImportTests {
    private let bo6Export: Any = ["multiplayer": [["Weapons": [["WeaponName": "Knife", "CurrentLevel": 5]]]]]
    private let bo7Export: Any = [["Weapons": [["WeaponName": "Knife", "CurrentLevel": 5]]]]

    private func game(_ id: String) throws -> Game { try #require(GameRegistry.game(id)) }

    @Test func eachGameTakesItsOwnExport() throws {
        #expect(LegacyImport.exportGame(bo6Export) == "bo6")
        #expect(LegacyImport.exportGame(bo7Export) == "bo7")
        #expect(LegacyImport.exportGame(["weapons": bo7Export]) == "bo7")
        #expect(LegacyImport.exportGame(["something": 1]) == nil)
        try LegacyImport.check(bo6Export, isFor: game("bo6"))
        try LegacyImport.check(bo7Export, isFor: game("bo7"))
    }

    @Test func theOtherGamesExportIsRefused() throws {
        let bo6 = try game("bo6"), bo7 = try game("bo7")
        do {
            try LegacyImport.check(bo6Export, isFor: bo7)
            Issue.record("BO6's export went into BO7")
        } catch LegacyImport.Failure.otherGame(let other) {
            #expect(other.id == "bo6")
        }
        do {
            try LegacyImport.check(bo7Export, isFor: bo6)
            Issue.record("BO7's export went into BO6")
        } catch LegacyImport.Failure.otherGame(let other) {
            #expect(other.id == "bo7")
        }
    }
}
