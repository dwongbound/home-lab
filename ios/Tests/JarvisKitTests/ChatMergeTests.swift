// Laying a fresh history page over what Chat shows keeps every row it
// already drew (Dylan, 2026-11-20: blank Chat, then everything flashing in).
import XCTest
@testable import JarvisKit

final class ChatMergeTests: XCTestCase {
    private func held(_ id: String, _ turn: Int?, user: Bool, _ text: String) -> MergeLine {
        MergeLine(id: id, turnId: turn, isUser: user, text: text)
    }
    private func fresh(_ turn: Int?, user: Bool, _ text: String) -> MergeLine {
        MergeLine(turnId: turn, isUser: user, text: text)
    }
    private var counter = 0
    private func newId() -> String { counter += 1; return "new-\(counter)" }

    /// The ids the merged list would show, in order.
    private func merged(_ held: [MergeLine], _ fresh: [MergeLine], keepOlder: Bool = true) -> [String] {
        let plan = ChatMerge.plan(held: held, fresh: fresh, keepOlder: keepOlder, newId: newId)
        return plan.older.map { held[$0].id } + plan.fresh.map(\.id) + plan.tail.map { held[$0].id }
    }

    func testNewTurnsAreAppendedAndHeldRowsKeepTheirIdentity() {
        let list = [held("a", 1, user: true, "hi"), held("b", 2, user: false, "hello")]
        let page = [fresh(1, user: true, "hi"), fresh(2, user: false, "hello"),
                    fresh(3, user: true, "and"), fresh(4, user: false, "so")]
        XCTAssertEqual(merged(list, page), ["a", "b", "turn-3", "turn-4"])
    }

    func testNothingNewChangesNothing() {
        let list = [held("a", 1, user: true, "hi"), held("b", 2, user: false, "hello")]
        let page = [fresh(1, user: true, "hi"), fresh(2, user: false, "hello")]
        XCTAssertEqual(merged(list, page), ["a", "b"])
    }

    func testARepeatedTurnInThePageIsShownOnce() {
        let page = [fresh(1, user: true, "hi"), fresh(1, user: true, "hi"), fresh(2, user: false, "yo")]
        XCTAssertEqual(merged([], page), ["turn-1", "turn-2"])
    }

    func testABubbleSentFromThePhoneMatchesItsTurnByTheTurnEventId() {
        // The stream's first event gave the bubble its turn id; its row
        // was made before that, with a random identity.
        let list = [held("a", 1, user: true, "hi"), held("b", 2, user: false, "hello"),
                    held("local-me", 3, user: true, "what's on"), held("local-reply", nil, user: false, "Two things")]
        let page = [fresh(1, user: true, "hi"), fresh(2, user: false, "hello"),
                    fresh(3, user: true, "what's on"), fresh(4, user: false, "Two things")]
        XCTAssertEqual(merged(list, page), ["a", "b", "local-me", "local-reply"])
    }

    func testABubbleWithNoTurnIdYetMatchesBySpeakerAndText() {
        let list = [held("a", 1, user: true, "hi"), held("local", nil, user: true, "ok 118")]
        let page = [fresh(1, user: true, "hi"), fresh(2, user: true, "ok 118")]
        XCTAssertEqual(merged(list, page), ["a", "local"])
    }

    func testOrderComesFromHistory() {
        let list = [held("b", 2, user: false, "two"), held("a", 1, user: true, "one")]
        let page = [fresh(1, user: true, "one"), fresh(2, user: false, "two")]
        XCTAssertEqual(merged(list, page), ["a", "b"])
    }

    func testOlderPagesHeScrolledThroughStay() {
        let list = (1...6).map { held("r\($0)", $0, user: $0 % 2 == 1, "t\($0)") }
        let page = (4...7).map { fresh($0, user: $0 % 2 == 1, "t\($0)") }
        XCTAssertEqual(merged(list, page), ["r1", "r2", "r3", "r4", "r5", "r6", "turn-7"])
    }

    func testAPageThatDoesNotContinueTheListReplacesIt() {
        // Too much happened in between: no gap is left in the middle.
        let list = [held("a", 1, user: true, "one"), held("b", 2, user: false, "two")]
        let page = [fresh(40, user: true, "forty"), fresh(41, user: false, "forty-one")]
        XCTAssertEqual(merged(list, page), ["turn-40", "turn-41"])
    }

    func testAMessageStillGoingOutStaysAfterThePage() {
        let list = [held("a", 1, user: true, "hi"), held("b", 2, user: false, "hello"),
                    held("sending", nil, user: true, "new one"), held("streaming", nil, user: false, "")]
        let page = [fresh(1, user: true, "hi"), fresh(2, user: false, "hello")]
        XCTAssertEqual(merged(list, page), ["a", "b", "sending", "streaming"])
    }

    func testAWindowRoundOneTurnReplacesTheList() {
        let list = (1...4).map { (n: Int) in held("r\(n)", n, user: true, "t\(n)") }
        let page = (3...5).map { fresh($0, user: true, "t\($0)") }
        XCTAssertEqual(merged(list, page, keepOlder: false), ["r3", "r4", "turn-5"])
    }

    /// A Talk session's exchanges land in Chat while he's still on Talk:
    /// the history load after each one (and one more when the call ends)
    /// lays them over the list, so Chat already shows them before he
    /// swipes over, with nothing reloaded on arrival.
    func testTalkTurnsArriveWithoutRedrawingTheChat() {
        let before = [held("a", 10, user: true, "lunch?"), held("b", 11, user: false, "Logged.")]
        let afterTalk = [fresh(10, user: true, "lunch?"), fresh(11, user: false, "Logged."),
                         fresh(12, user: true, "lights off"), fresh(13, user: false, "Done.")]
        let ids = merged(before, afterTalk)
        XCTAssertEqual(ids, ["a", "b", "turn-12", "turn-13"])
        // The same page again (the quiet load as the call ends) changes nothing.
        let shown = zip(ids, afterTalk).map { MergeLine(id: $0, turnId: $1.turnId, isUser: $1.isUser, text: $1.text) }
        XCTAssertEqual(merged(shown, afterTalk), ids)
    }
}

final class ChatScreenTests: XCTestCase {
    func testPlaceholdersFromTheFirstFrameUntilMessagesArrive() {
        XCTAssertEqual(ChatScreen.state(hasItems: false, loaded: false, failed: false), .loading)
    }

    func testMessagesWinWhateverElseIsTrue() {
        XCTAssertEqual(ChatScreen.state(hasItems: true, loaded: false, failed: true), .messages)
        XCTAssertEqual(ChatScreen.state(hasItems: true, loaded: true, failed: false), .messages)
    }

    func testAFailedFirstLoadSaysSoInsteadOfShowingNothing() {
        XCTAssertEqual(ChatScreen.state(hasItems: false, loaded: false, failed: true), .failed)
    }

    func testATrulyEmptyChatSaysSo() {
        XCTAssertEqual(ChatScreen.state(hasItems: false, loaded: true, failed: false), .empty)
    }

    func testTheFirstLoadTriesSeveralTimesOverAboutFifteenSeconds() {
        XCTAssertEqual(ChatScreen.retryWaits.first, 0)
        XCTAssertGreaterThanOrEqual(ChatScreen.retryWaits.count, 4)
        XCTAssertLessThanOrEqual(ChatScreen.retryWaits.reduce(0, +), 20)
    }
}

final class ChatScrollTests: XCTestCase {
    /// The numbers measured at the very bottom of Chat in the simulator on
    /// 2026-11-20 (content 4962, offset 4149, visible 682, insets 118 top
    /// and 156 bottom): about 13 pt from the end. The old sum said 287.
    func testTheVeryBottomCountsAsTheBottom() {
        let gap = ChatScroll.gap(contentHeight: 4962, offsetY: 4149, visibleHeight: 682, insetTop: 118)
        XCTAssertEqual(gap, 13, accuracy: 0.5)
        let state = ChatScroll.next(gap: gap, byHand: true, atBottom: false, readingUp: true)
        XCTAssertTrue(state.atBottom)
        XCTAssertFalse(state.readingUp)
    }

    func testScrollingUpByHandIsReadingUp() {
        let state = ChatScroll.next(gap: 400, byHand: true, atBottom: true, readingUp: false)
        XCTAssertFalse(state.atBottom)
        XCTAssertTrue(state.readingUp)
    }

    func testAScrollHeDidNotMakeIsNotReadingUp() {
        // A reply growing, or the list settling: not him reading up.
        let state = ChatScroll.next(gap: 400, byHand: false, atBottom: true, readingUp: false)
        XCTAssertFalse(state.readingUp)
    }

    func testBetweenTheThresholdsNothingFlips() {
        XCTAssertEqual(ChatScroll.next(gap: 80, byHand: true, atBottom: true, readingUp: true).atBottom, true)
        XCTAssertEqual(ChatScroll.next(gap: 80, byHand: true, atBottom: false, readingUp: true).readingUp, true)
    }
}

final class NewReplyDotTests: XCTestCase {
    func testOlderMessagesArrivingAtTheTopDontLightIt() {
        // The last line is the same, and no longer.
        let changed = NewReplyDot.endChanged(oldLastId: "turn-9", oldLastLength: 20, newLastId: "turn-9", newLastLength: 20)
        XCTAssertFalse(changed)
        XCTAssertFalse(NewReplyDot.lights(endChanged: changed, lastIsJarvis: true, atBottom: false, sending: false))
    }

    func testANewReplyWhileScrolledUpLightsIt() {
        let changed = NewReplyDot.endChanged(oldLastId: "turn-9", oldLastLength: 20, newLastId: "turn-10", newLastLength: 5)
        XCTAssertTrue(NewReplyDot.lights(endChanged: changed, lastIsJarvis: true, atBottom: false, sending: false))
    }

    func testAReplyStillStreamingCountsAsNew() {
        XCTAssertTrue(NewReplyDot.endChanged(oldLastId: "r", oldLastLength: 10, newLastId: "r", newLastLength: 40))
    }

    func testAtTheBottomOrWaitingOnHisOwnMessageItStaysOff() {
        XCTAssertFalse(NewReplyDot.lights(endChanged: true, lastIsJarvis: true, atBottom: true, sending: false))
        XCTAssertFalse(NewReplyDot.lights(endChanged: true, lastIsJarvis: true, atBottom: false, sending: true))
        XCTAssertFalse(NewReplyDot.lights(endChanged: true, lastIsJarvis: false, atBottom: false, sending: false))
    }
}

final class HomeScreenTests: XCTestCase {
    func testTheLoaderShowsUntilTheFirstSnapshot() {
        XCTAssertEqual(HomeScreen.state(hasSnapshot: false, firstLoadFailed: false), .loading)
        XCTAssertEqual(HomeScreen.state(hasSnapshot: true, firstLoadFailed: false), .ready)
    }

    func testARefreshNeverBringsTheLoaderBack() {
        // Once there's a snapshot, a failed refresh keeps the page.
        XCTAssertEqual(HomeScreen.state(hasSnapshot: true, firstLoadFailed: true), .ready)
    }

    func testAFailedFirstLoadSaysSo() {
        XCTAssertEqual(HomeScreen.state(hasSnapshot: false, firstLoadFailed: true), .failed)
    }

    func testFirstRetriesAreQuickThenTheUsualPace() {
        XCTAssertEqual((1...5).map { HomeScreen.retryWait(misses: $0, usual: 15) }, [1, 2, 4, 8, 15])
        XCTAssertEqual(HomeScreen.retryWait(misses: 0, usual: 15), 15)
    }
}

final class HomeGiveUpTests: XCTestCase {
    func testGivesUpAfterFourMissesOrTenSeconds() {
        XCTAssertFalse(HomeScreen.gaveUp(misses: 1, sinceFirstTry: 3))
        XCTAssertTrue(HomeScreen.gaveUp(misses: 4, sinceFirstTry: 3))
        XCTAssertTrue(HomeScreen.gaveUp(misses: 1, sinceFirstTry: 12))
    }
}
