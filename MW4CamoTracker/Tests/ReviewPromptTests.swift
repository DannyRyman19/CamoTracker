import Testing
import Foundation

@Suite("Rating prompt gate")
struct ReviewPromptTests {

    /// A throwaway defaults suite per test, so nothing leaks between them or
    /// into the machine running them.
    private func defaults() -> UserDefaults {
        let name = "ReviewPromptTests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name)!
    }

    @Test func staysShutBelowTheFirstMilestoneAndOpensAtIt() async {
        let d = defaults()
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 0, defaults: d) == false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 4, defaults: d) == false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == true)
    }

    @Test func eachMilestoneIsWorthOnePromptOnly() async {
        let d = defaults()
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == true)
        await ReviewPrompt.markPrompted(weaponsComplete: 5, defaults: d, onTestFlight: false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 14, defaults: d) == false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 20, defaults: d) == true)
    }

    /// A count that arrives in a jump - an imported save, or a correction that
    /// completes several weapons at once - still earns its prompt rather than
    /// sailing past the exact threshold.
    @Test func aCountThatArrivesInAJumpStillEarnsItsPrompt() async {
        let d = defaults()
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 37, defaults: d) == true)
        await ReviewPrompt.markPrompted(weaponsComplete: 37, defaults: d, onTestFlight: false)
        // 20 was the milestone credited, so 50 is still ahead.
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 49, defaults: d) == false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 50, defaults: d) == true)
    }

    /// The presentation guard can suppress a prompt after the gate opened
    /// (the milestone banner is still up). That must not burn the milestone:
    /// markPrompted is what spends it, not shouldAsk.
    @Test func aSuppressedPromptIsRetriedRatherThanBurned() async {
        let d = defaults()
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == true)
        // Guard bailed, no markPrompted. The next finished weapon asks again.
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 6, defaults: d) == true)
    }

    /// requestReview does nothing on TestFlight, so spending a milestone there
    /// would leave the tester unable to see that prompt ever again, including
    /// once the App Store build reached them.
    @Test func testFlightSpendsNoMilestone() async {
        let d = defaults()
        await ReviewPrompt.markPrompted(weaponsComplete: 5, defaults: d, onTestFlight: true)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == true,
                      "a TestFlight build burned a milestone it could not show")

        await ReviewPrompt.markPrompted(weaponsComplete: 5, defaults: d, onTestFlight: false)
        await #expect(ReviewPrompt.shouldAsk(weaponsComplete: 5, defaults: d) == false)
    }
}
