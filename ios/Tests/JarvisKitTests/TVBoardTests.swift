import XCTest
@testable import JarvisKit

final class TVBoardTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    /// 2026-11-17 at hh:mm in Los Angeles.
    private func at(_ h: Int, _ m: Int = 0, day: Int = 17) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    func testCountdownWords() {
        let now = at(12)
        XCTAssertEqual(Countdown.words(from: now, to: now), "now")
        XCTAssertEqual(Countdown.words(from: now, to: at(12, 5)), "in 5 min")
        XCTAssertEqual(Countdown.words(from: now, to: at(13, 20)), "in 1 h 20 min")
        XCTAssertEqual(Countdown.words(from: now, to: at(14)), "in 2 h")
        XCTAssertEqual(Countdown.words(from: now, to: at(16, 40)), "in 4 h")
        XCTAssertEqual(Countdown.left(from: now, to: at(12, 42)), "42 min left")
        XCTAssertEqual(Countdown.left(from: now, to: at(13, 5)), "1 h 5 min left")
    }

    func testNowNextPrefersWhatIsOnThenNextSkippingJarvisJobs() {
        let events = [
            CalendarEvent(id: "a", title: "Lunch with Sam", start: iso(at(12)), end: iso(at(13)), location: "Tender Greens"),
            CalendarEvent(id: "b", title: "Rehearsal", start: iso(at(20)), end: iso(at(22))),
        ]
        let agenda = [AgendaItem(id: "jarvis-x@0830", at: iso(at(12, 30)), title: "Marketplace scan", detail: "Jarvis: scan", allDay: nil)]
        let lunch = NowNext.pick(events: events, agenda: agenda, now: at(12, 18), calendar: la)
        XCTAssertEqual(lunch?.kind, .now)
        XCTAssertEqual(lunch?.location, "Tender Greens")
        XCTAssertEqual(lunch?.countdown(now: at(12, 18)), "42 min left")
        XCTAssertEqual(lunch?.progress(now: at(12, 30)) ?? 0, 0.5, accuracy: 0.001)

        let next = NowNext.pick(events: events, agenda: agenda, now: at(15), calendar: la)
        XCTAssertEqual(next?.kind, .next)
        XCTAssertEqual(next?.title, "Rehearsal")
        XCTAssertEqual(next?.countdown(now: at(15)), "in 5 h")
    }

    func testAfterGivesWhatFollowsTheEventOnNow() {
        let events = [
            CalendarEvent(id: "a", title: "Lunch with Sam", start: iso(at(12)), end: iso(at(13)), location: "Tender Greens"),
            CalendarEvent(id: "b", title: "Rehearsal", start: iso(at(20)), end: iso(at(22))),
            CalendarEvent(id: "c", title: "Dentist", start: iso(at(9, day: 18)), end: nil),
        ]
        let after = NowNext.after(events: events, agenda: [], now: at(12, 18), calendar: la)
        XCTAssertEqual(after?.title, "Rehearsal")
        XCTAssertEqual(after?.when(timeZone: la.timeZone), "8:00 PM")
        // Nothing on now: the pick itself is the next one, so no "after".
        XCTAssertNil(NowNext.after(events: events, agenda: [], now: at(15), calendar: la))
        // On now in the evening with nothing else today: tomorrow's first.
        let late = NowNext.after(events: events, agenda: [], now: at(21), calendar: la)
        XCTAssertEqual(late?.kind, .tomorrow)
        XCTAssertEqual(late?.when(timeZone: la.timeZone), "Tomorrow 9:00 AM")
    }

    func testTomorrowShowsOnlyInTheEveningWhenTodayIsDone() {
        let events = [CalendarEvent(id: "c", title: "Dentist", start: iso(at(9, day: 18)), end: nil)]
        XCTAssertNil(NowNext.pick(events: events, agenda: [], now: at(15), calendar: la))
        let evening = NowNext.pick(events: events, agenda: [], now: at(21), calendar: la)
        XCTAssertEqual(evening?.kind, .tomorrow)
        XCTAssertEqual(evening?.countdown(now: at(21), timeZone: la.timeZone), "9:00 AM")
    }

    func testAgendaItemsCountWhenThereIsNoCalendar() {
        let agenda = [AgendaItem(id: "1", at: iso(at(18)), title: "Volleyball", detail: nil, allDay: nil)]
        XCTAssertEqual(NowNext.pick(events: [], agenda: agenda, now: at(17, 18), calendar: la)?.countdown(now: at(17, 18)), "in 42 min")
    }

    func testSunArcRunsSunriseToSunsetAndTheMoonAtNight() {
        let rise = at(6, 30), set = at(16, 30)
        let noon = SkyArc.at(now: at(11, 30), sunrise: rise, sunset: set)
        XCTAssertTrue(noon.sun)
        XCTAssertEqual(noon.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(noon.height, 1, accuracy: 0.001)
        XCTAssertEqual(SkyArc.at(now: at(6, 30), sunrise: rise, sunset: set).progress, 0, accuracy: 0.001)
        let lateNight = SkyArc.at(now: at(23, 30), sunrise: rise, sunset: set)
        XCTAssertFalse(lateNight.sun)
        XCTAssertEqual(lateNight.progress, 0.5, accuracy: 0.01)
        let earlyMorning = SkyArc.at(now: at(2), sunrise: rise, sunset: set)
        XCTAssertFalse(earlyMorning.sun)
        XCTAssertGreaterThan(earlyMorning.progress, 0.6)
    }

    func testStarsFadeWithTheLight() {
        XCTAssertEqual(SkyArc.stars(SunLampState(phase: .night, brightness: 0.03, warmth: 0)), 1, accuracy: 0.01)
        XCTAssertEqual(SkyArc.stars(SunLampState(phase: .day, brightness: 1, warmth: 0)), 0)
    }

    func testTimelineMarksDoneNowNextAndKeepsTheFuture() {
        let items = (0..<8).map { i in AgendaItem(id: "\(i)", at: iso(at(8 + 2 * i)), title: "Item \(i)", detail: nil, allDay: nil) }
        let rows = TodayTimeline.rows(items, now: at(14, 30), limit: 5, timeZone: la.timeZone)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.state), [.now, .next, .later, .later, .later])
        XCTAssertEqual(rows.first?.time, "2:00 PM")
    }

    func testGuestModeHidesPrivateCards() throws {
        let json = #"{"generatedAt":"x","services":[{"id":"h","name":"Home Assistant","detail":"","status":"up"}],"today":[{"id":"1","at":"2026-11-17T20:00:00Z","title":"x"}],"offers":{"greeting":"Evening, Dylan. You're at Varda.","offers":[{"id":"o","title":"t","body":"b","startText":"s"}]},"cloud":{"health":{"yesterday":{"steps":100}}}}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        // Jarvis's message leads the rotation, guests included.
        XCTAssertEqual(TVBoard.cards(s, guest: false), [.message, .today, .jarvis, .health, .suggestions])
        XCTAssertEqual(TVBoard.cards(s, guest: true), [.message, .today, .jarvis])
        XCTAssertEqual(TVBoard.greeting(s, guest: true)?.body, "You're at Varda.")
    }

    func testForecastAndCalendarDecodeAndBadSectionsAreSkipped() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"home":{"devices":[],"forecast":[{"at":"2026-11-17T20:00:00Z","condition":"rainy","temperature":61,"rain":40}]},"cloud":{"calendar":[{"id":"e","title":"Dinner","start":"2026-11-17T20:00:00-08:00","end":"2026-11-17T21:00:00-08:00","allDay":false,"location":"Home"}],"money":"broken"}}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.home?.forecast?.first?.rain, 40)
        XCTAssertEqual(s.events.first?.location, "Home")
        XCTAssertNil(s.money)
    }

    func testStatusChipsCountApprovalsAndFallBackToCalm() throws {
        let calm = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[]}"#.utf8))
        XCTAssertEqual(StatusChips.chips(calm, approvals: 0).map(\.text), ["All systems normal"])
        let busy = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[{"id":"o","name":"Ollama","detail":"","status":"down"}],"today":[],"jobs":{"running":[{"id":"j","label":"x","state":"running"}]}}"#.utf8))
        XCTAssertEqual(StatusChips.chips(busy, approvals: 2).map(\.text), ["Ollama down", "2 approvals waiting", "Jarvis is working"])
    }

    func testLongStretchesLeftInWholeHours() {
        XCTAssertEqual(Countdown.left(from: at(15, 11), to: at(19, 30)), "4 h left")
    }

    func testTimelineMergesCalendarEventsAndGuestsDontSeeJarvisJobs() {
        let agenda = [AgendaItem(id: "jarvis-a@1800", at: iso(at(18)), title: "Follow up with Aditya", detail: "Jarvis: reminder", allDay: nil)]
        let events = [CalendarEvent(id: "v", title: "Varda", start: iso(at(11)), end: iso(at(19, 30)), location: "555 Somewhere")]
        let full = TodayTimeline.rows(agenda, events: events, now: at(15), timeZone: la.timeZone, calendar: la)
        XCTAssertEqual(full.map(\.title), ["Varda", "Follow up with Aditya"])
        XCTAssertEqual(full.map(\.state), [.now, .next])
        let guest = TodayTimeline.rows(agenda, events: events, now: at(15), guest: true, timeZone: la.timeZone, calendar: la)
        XCTAssertEqual(guest.map(\.title), ["Varda"])
    }

    func testGuestsDontSeeWhereTheHeroIs() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"cloud":{"calendar":[{"id":"v","title":"Varda","start":"\#(iso(at(11)))","end":"\#(iso(at(19, 30)))","location":"555 Somewhere"}]}}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(TVBoard.hero(s, now: at(15), guest: false)?.location, "555 Somewhere")
        XCTAssertNil(TVBoard.hero(s, now: at(15), guest: true)?.location)
        XCTAssertEqual(TVBoard.hero(s, now: at(15), guest: true)?.title, "Varda")
    }

    func testForecastShowsTheMoonAfterDark() {
        let rise = at(6, 30), set = at(16, 48)
        let evening = ForecastHour(at: iso(at(20)), condition: "sunny", temperature: 60, low: nil, rain: nil)
        let afternoon = ForecastHour(at: iso(at(14)), condition: "sunny", temperature: 66, low: nil, rain: nil)
        let cloudyNight = ForecastHour(at: iso(at(21)), condition: "partlycloudy", temperature: 58, low: nil, rain: nil)
        XCTAssertEqual(TVBoard.forecastSymbol(evening, sunrise: rise, sunset: set), "moon.stars.fill")
        XCTAssertEqual(TVBoard.forecastSymbol(afternoon, sunrise: rise, sunset: set), "sun.max.fill")
        XCTAssertEqual(TVBoard.forecastSymbol(cloudyNight, sunrise: rise, sunset: set), "cloud.moon.fill")
    }
}

final class NightCalmTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: h, minute: m))!
    }
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    func testCalmFromHalfPastTwoToHalfAnHourBeforeSunrise() {
        let rise = at(6, 30)
        XCTAssertFalse(NightCalm.isCalm(now: at(23, 30), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        XCTAssertFalse(NightCalm.isCalm(now: at(0, 5), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        XCTAssertFalse(NightCalm.isCalm(now: at(2, 29), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        XCTAssertTrue(NightCalm.isCalm(now: at(2, 30), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        XCTAssertTrue(NightCalm.isCalm(now: at(5, 59), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        XCTAssertFalse(NightCalm.isCalm(now: at(6, 0), sunrise: rise, enabled: true, wokenUntil: nil, calendar: la))
        // Yesterday's sunrise time still works.
        XCTAssertTrue(NightCalm.isCalm(now: at(3), sunrise: rise.addingTimeInterval(-86_400), enabled: true, wokenUntil: nil, calendar: la))
    }

    func testOffSwitchAndARemotePressWakeIt() {
        XCTAssertFalse(NightCalm.isCalm(now: at(3), sunrise: at(6, 30), enabled: false, wokenUntil: nil, calendar: la))
        XCTAssertFalse(NightCalm.isCalm(now: at(3), sunrise: at(6, 30), enabled: true, wokenUntil: at(3, 1), calendar: la))
        XCTAssertTrue(NightCalm.isCalm(now: at(3, 2), sunrise: at(6, 30), enabled: true, wokenUntil: at(3, 1), calendar: la))
    }

    func testMorningLineOnlyBeforeTen() {
        let events = [CalendarEvent(id: "d", title: "Dentist", start: iso(at(9)), end: nil),
                      CalendarEvent(id: "l", title: "Lunch", start: iso(at(12)), end: nil)]
        XCTAssertEqual(NightCalm.morningLine(events: events, agenda: [], now: at(2), guest: true, calendar: la, timeZone: la.timeZone), "Dentist at 9:00 AM")
        XCTAssertNil(NightCalm.morningLine(events: [events[1]], agenda: [], now: at(2), guest: true, calendar: la, timeZone: la.timeZone))
    }

    func testLookoutCardIsPrivateAndCountsMessages() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"jobs":{"running":[],"lookout":{"checks":["calendar"],"watching":["Flight prices to Tokyo"],"heldBack":[{"text":"private","reason":null}]},"messenger":{"sentToday":3,"cap":8,"quiet":"10 PM–7 AM"}}}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(s.jobs?.lookout?.watching, ["Flight prices to Tokyo"])
        XCTAssertEqual(s.jobs?.lookout?.heldBackCount, 1)
        XCTAssertTrue(TVBoard.cards(s, guest: false).contains(.lookout))
        XCTAssertFalse(TVBoard.cards(s, guest: true).contains(.lookout))
        XCTAssertEqual(LookoutCard.messagesLine(s.jobs?.messenger), "3 of 8 messages today")
        XCTAssertEqual(LookoutCard.messagesLine(Messenger(sentToday: 0, cap: 8, quiet: nil)), "No messages today")
    }
}

final class TaskCardTests: XCTestCase {
    func testTasksCardOnlyWhileSomethingRunsAndGuestsSeeNoNames() throws {
        let idle = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[]}"#.utf8))
        XCTAssertFalse(TVBoard.cards(idle, guest: false).contains(.tasks))
        let busy = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[],"jobs":{"running":[{"id":"j","label":"Booking flights to Tokyo","state":"running"}]}}"#.utf8))
        XCTAssertTrue(TVBoard.cards(busy, guest: true).contains(.tasks))
        let task = busy.jobs!.running[0]
        XCTAssertEqual(TaskCard.title(task, index: 0, guest: true), "Task 1")
        XCTAssertEqual(TaskCard.title(task, index: 0, guest: false), "Booking flights to Tokyo")
    }
}

final class CardSwipeTests: XCTestCase {
    func testWrapsBothWays() {
        XCTAssertEqual(CardSwipe.index(turn: 0, count: 4), 0)
        XCTAssertEqual(CardSwipe.index(turn: 5, count: 4), 1)
        XCTAssertEqual(CardSwipe.index(turn: -1, count: 4), 3)
        XCTAssertEqual(CardSwipe.index(turn: -5, count: 4), 3)
        XCTAssertEqual(CardSwipe.index(turn: 3, count: 0), 0)
    }

    func testRotationWaitsAMinuteAfterASwipe() {
        let now = Date()
        XCTAssertTrue(CardSwipe.autoAdvanceAllowed(lastSwipe: nil, now: now))
        XCTAssertFalse(CardSwipe.autoAdvanceAllowed(lastSwipe: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(CardSwipe.autoAdvanceAllowed(lastSwipe: now.addingTimeInterval(-61), now: now))
    }

    /// The Devices card joins the rotation after Home whenever there are
    /// devices, guests included (it's the house, not Dylan).
    func testDevicesCardFollowsHomeWhenThereAreDevices() throws {
        let json = #"{"generatedAt":"x","services":[],"today":[],"home":{"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"heat","detail":"heating","current":68,"target":70},{"id":"l","name":"Bedroom Lamp","kind":"light","state":"on"}]}}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let cards = TVBoard.cards(s, guest: false)
        XCTAssertTrue(cards.contains(.devices))
        if let home = cards.firstIndex(of: .home), let devices = cards.firstIndex(of: .devices) {
            XCTAssertEqual(devices, home + 1)
        }
        XCTAssertTrue(TVBoard.cards(s, guest: true).contains(.devices))
        let none = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","services":[],"today":[]}"#.utf8))
        XCTAssertFalse(TVBoard.cards(none, guest: false).contains(.devices))
    }
}
