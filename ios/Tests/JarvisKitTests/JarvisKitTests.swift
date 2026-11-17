// Checks the pieces the app's screens trust: reading the chat stream, the
// approval and model wording (same as the web page's), the snapshot slice,
// and the headers the server insists on.
import XCTest
@testable import JarvisKit

final class ChatEventTests: XCTestCase {
    /// Each event type the stream sends reads back as the right case.
    func testParsesEveryEventType() {
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"delta","text":"Hi"}"#), .delta("Hi"))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"done","ok":true}"#), .done)
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"error","message":"Oops"}"#), .error("Oops"))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"working","label":"Searching the web."}"#), .working("Searching the web."))
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"working_done"}"#), .workingDone)
        XCTAssertEqual(ChatEvent.parse(line: #"{"type":"model","model":"claude"}"#), .model("claude"))
        XCTAssertEqual(
            ChatEvent.parse(line: #"{"type":"approval","approval":{"id":"a1","tool":"run_command","summary":"List files","expires":"2026-11-17T03:00:00Z"}}"#),
            .approval(Approval(id: "a1", tool: "run_command", summary: "List files", expires: "2026-11-17T03:00:00Z"))
        )
        XCTAssertEqual(
            ChatEvent.parse(line: #"{"type":"approval_done","id":"a1","ok":false,"by":"voice","later":true}"#),
            .approvalDone(id: "a1", ok: false, by: "voice", later: true)
        )
    }

    /// Blank lines, junk and event types from a newer Jarvis are skipped, not fatal.
    func testSkipsWhatItDoesNotKnow() {
        XCTAssertNil(ChatEvent.parse(line: ""))
        XCTAssertNil(ChatEvent.parse(line: "not json"))
        XCTAssertNil(ChatEvent.parse(line: #"{"type":"something_new"}"#))
        XCTAssertNil(ChatEvent.parse(line: #"{"type":"approval","approval":{"id":"a1"}}"#))
    }
}

final class WordingTests: XCTestCase {
    /// Known tools get words; unknown ones get the general ask.
    func testToolLabels() {
        XCTAssertEqual(ApprovalWording.toolLabel("run_command"), "Run a command")
        XCTAssertEqual(ApprovalWording.toolLabel("change_code"), "Change Jarvis’s code")
        XCTAssertEqual(ApprovalWording.toolLabel("google_calendar_update"), "Needs your OK")
    }

    /// Plain summaries pass through; raw tool calls lose their ids.
    func testReadableSummary() {
        XCTAssertEqual(ApprovalWording.readableSummary("Living room: heat to 70°"), "Living room: heat to 70°")
        XCTAssertEqual(
            ApprovalWording.readableSummary("Google Calendar delete_event (eventId=abc123def456ghi789jkl0)"),
            "Google Calendar: delete event"
        )
        XCTAssertEqual(
            ApprovalWording.readableSummary("send to someone@example.com now"),
            "Jarvis wants to make a change. Ask him what it is before saying yes."
        )
    }

    /// Outcome lines match the web page's.
    func testOutcomeText() {
        XCTAssertEqual(ApprovalWording.outcomeText(ok: true, later: false, by: "page"), "Approved")
        XCTAssertEqual(ApprovalWording.outcomeText(ok: false, later: false, by: "voice"), "Denied out loud")
        XCTAssertEqual(ApprovalWording.outcomeText(ok: true, later: false, by: "telegram"), "Approved on Telegram")
        XCTAssertEqual(ApprovalWording.outcomeText(ok: false, later: false, by: "timeout"), "No answer in time, so he left it alone")
        XCTAssertEqual(ApprovalWording.outcomeText(ok: false, later: true, by: "voice"), "Holding this for later. Say “go ahead” when you’re ready.")
    }

    /// The model chip: C for Claude (orange), O for Ornith (blue), nothing when unknown.
    func testModelChip() {
        XCTAssertEqual(ModelWording.label("claude"), "Jarvis (C)")
        XCTAssertEqual(ModelWording.label("ornith"), "Jarvis (O)")
        XCTAssertEqual(ModelWording.label("  "), "")
        XCTAssertTrue(ModelWording.isClaude(" Claude "))
        XCTAssertFalse(ModelWording.isClaude("ornith"))
    }
}

final class SnapshotTests: XCTestCase {
    /// A full snapshot keeps what Today needs and ignores the rest.
    func testDecodesTodaySlice() throws {
        let json = """
        {"generatedAt":"2026-11-17T02:00:00Z","source":"live",
         "today":[{"id":"e1","at":"2026-11-17T06:00:00Z","title":"Study block","detail":"","status":"scheduled","allDay":false}],
         "offers":{"greeting":"Evening, Dylan.","offers":[{"id":"o1","title":"Rental car","body":"Dallas trip","startText":"Find me a rental car","created":null}]},
         "home":{"devices":[{"id":"climate.living","name":"Living room","kind":"climate","state":"heat","available":true,"current":68,"target":70}],"weather":{"condition":"clear","temperature":61,"unit":"°F"},"sun":{"rising":null,"setting":null}},
         "services":[{"id":"ha","name":"Home Assistant","detail":"","status":"down"},{"id":"jarvis","name":"Jarvis","detail":"","status":"up"}],
         "jobs":{"generatedAt":null,"jobs":[],"lookout":null,"messenger":null,"running":[{"id":"t1","label":"Rental cars","state":"running","startedAt":null}]},
         "metrics":[],"moneyPicks":{"picks":[]}}
        """
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.today.first?.title, "Study block")
        XCTAssertEqual(snapshot.offers?.greeting, "Evening, Dylan.")
        XCTAssertEqual(snapshot.thermostat?.target, 70)
        XCTAssertEqual(snapshot.alerts.map(\.id), ["ha"])
        XCTAssertEqual(snapshot.jobs?.running.first?.label, "Rental cars")
    }

    /// Missing sections (no Home Assistant, an older Jarvis) still decode.
    func testDecodesWithSectionsMissing() throws {
        let json = #"{"generatedAt":"x","today":[],"home":null,"offers":null,"jobs":{"jobs":[]}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.home)
        XCTAssertNil(snapshot.thermostat)
        XCTAssertEqual(snapshot.jobs?.running.count, 0)
        XCTAssertTrue(snapshot.alerts.isEmpty)
    }

    /// Agenda times in Pacific time; all-day and odd values read sensibly.
    /// Money comes from the cloud digest; cash and card totals add up.
    func testDecodesMoney() throws {
        let json = #"{"generatedAt":"x","today":[],"services":[],"cloud":{"updatedAt":"y","threads":[],"money":{"netWorth":12000.4,"accounts":[{"id":"a","name":"Checking","institution":"Chase","kind":"cash","balance":1500},{"id":"b","name":"Forbright","institution":"F","kind":"cash","balance":25000},{"id":"c","name":"Amex","institution":"A","kind":"credit","balance":420.5}],"spending":{"thisMonth":1834,"lastMonthToDate":2100,"budget":null},"categories":[],"recent":[{"id":"t","date":"2026-11-16","merchant":"Trader Joe's","category":"Groceries","amount":54.2}],"flags":[{"id":"f","text":"New subscription: Netflix"}]}}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let money = try XCTUnwrap(snapshot.money)
        XCTAssertEqual(money.cash, 26500)
        XCTAssertEqual(money.cardDebt, 420.5)
        XCTAssertEqual(money.flags.first?.text, "New subscription: Netflix")
        XCTAssertEqual(money.recent.first?.merchant, "Trader Joe's")
        XCTAssertEqual(MoneyText.dollars(26500), "$26,500")
    }

    /// Devices read their on/off and extra fields; a broken cloud section is just no money.
    func testDevicesAndBrokenCloud() throws {
        let json = #"{"generatedAt":"x","today":[],"services":[],"cloud":{"money":"oops"},"home":{"devices":[{"id":"l","name":"Desk lamp","kind":"light","state":"on","available":true,"brightness":0.6},{"id":"t","name":"Thermostat","kind":"climate","state":"heat","current":68,"target":70}],"weather":null}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.money)
        XCTAssertEqual(snapshot.home?.devices.first?.brightness, 0.6)
        XCTAssertEqual(snapshot.home?.devices.map(\.isOn), [true, true])
    }

    func testAgendaTimeLabels() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(AgendaTime.label(at: "2026-11-17T06:00:00Z", allDay: false, timeZone: pacific), "10:00 PM")
        XCTAssertEqual(AgendaTime.label(at: "2026-11-17T06:00:00.000Z", allDay: false, timeZone: pacific), "10:00 PM")
        XCTAssertEqual(AgendaTime.label(at: "2026-11-17", allDay: true, timeZone: pacific), "All day")
        XCTAssertEqual(AgendaTime.label(at: "Tonight", allDay: false, timeZone: pacific), "Tonight")
    }
}

final class ClientTests: XCTestCase {
    /// Every request carries the header the server checks and a matching Origin.
    func testRequestHeaders() {
        let client = JarvisClient(base: URL(string: "https://jarvis.snakebird-ph.ts.net")!)
        let request = client.request("api/jarvis/approve", method: "POST", json: ["id": "a1", "ok": true])
        XCTAssertEqual(request.url?.absoluteString, "https://jarvis.snakebird-ph.ts.net/api/jarvis/approve")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-home-lab"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://jarvis.snakebird-ph.ts.net")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    /// "Can't reach" points at Tailscale, the usual cause.
    func testUnreachableWording() {
        XCTAssertEqual(JarvisError.unreachable.errorDescription, "Can’t reach Jarvis. Is Tailscale on?")
    }
}
