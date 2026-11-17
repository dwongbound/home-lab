// The Today tab's reading of the snapshot: money, health and home tiles.
import XCTest
@testable import JarvisKit

final class TodaySnapshotTests: XCTestCase {
    private let json = """
    {"generatedAt":"2026-11-17T08:00:00Z","today":[],"services":[],
     "home":{"devices":[
        {"id":"a","name":"Hall","kind":"light","state":"on","available":true},
        {"id":"b","name":"Bedroom","kind":"light","state":"unavailable","available":false},
        {"id":"c","name":"TV","kind":"media","state":"off","available":true},
        {"id":"d","name":"before_naming","kind":"scene","state":"2026-11-14T06:25:20Z"}],
      "weather":{"condition":"cloudy","temperature":58,"unit":"°F"},
      "sun":{"rising":"2026-11-17T14:28:36+00:00","setting":"2026-11-18T00:48:35+00:00"}},
     "cloud":{
      "money":{"netWorth":1000,"accounts":[
          {"id":"1","name":"Savings","kind":"cash","balance":500},
          {"id":"2","name":"Card","kind":"credit","balance":120.5},
          {"id":"3","name":"Card 2","kind":"credit","balance":0}],
        "spending":{"thisMonth":600,"lastMonthToDate":480,"budget":400},
        "categories":[{"name":"Food","spent":300,"budget":100},{"name":"Rent","spent":90,"budget":100},
                      {"name":"Other","spent":50,"budget":null},{"name":"Fun","spent":150,"budget":100}],
        "flags":[{"id":"f","text":"Food is over budget."}]},
      "health":{"yesterday":{"steps":9580,"activeKcal":489},"sleep":{"asleep_min":422,"deep_min":54,"rem_min":131}}}}
    """

    private func snapshot() throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    func testReadsMoneyAndHealth() throws {
        let s = try snapshot()
        XCTAssertEqual(s.money?.netWorth, 1000)
        XCTAssertEqual(s.money?.cardDebt, 120.5)
        XCTAssertEqual(s.money?.cash, 500)
        XCTAssertEqual(s.money?.overBudget.map(\.name), ["Food", "Fun"])
        XCTAssertEqual(s.money?.flags.first?.text, "Food is over budget.")
        XCTAssertEqual(s.health?.yesterday?.steps, 9580)
        XCTAssertEqual(s.health?.sleep?.asleepMin, 422)
        XCTAssertNotNil(s.home?.sun?.setting)
    }

    func testHomeTilesSkipScenesAndUnavailable() throws {
        let tiles = try snapshot().homeTiles
        XCTAssertEqual(tiles.map(\.name), ["Hall", "TV"])
        XCTAssertTrue(tiles[0].isOn)
        XCTAssertFalse(tiles[1].isOn)
    }

    func testOldSnapshotWithoutCloudStillDecodes() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"generatedAt":"x","today":[],"services":[]}"#.utf8))
        XCTAssertNil(s.money)
        XCTAssertNil(s.health)
        XCTAssertTrue(s.homeTiles.isEmpty)
    }
}

final class RunningTaskTests: XCTestCase {
    func testDecodesStartAndWords() throws {
        let json = #"{"running":[{"id":"a","label":"Changing my code","state":"running","startedAt":"2026-11-17T10:00:00Z"},{"id":"b","label":"Lookout sweep","state":"queued"}]}"#
        let jobs = try JSONDecoder().decode(Jobs.self, from: Data(json.utf8))
        let now = ISO8601DateFormatter().date(from: "2026-11-17T11:05:30Z")!
        XCTAssertEqual(jobs.running.count, 2)
        XCTAssertEqual(jobs.running[0].runningWords(now: now), "Running for 1 h 5 min")
        XCTAssertEqual(jobs.running[1].runningWords(now: now), "Queued")
        let fresh = RunningTask(id: "c", label: "x", state: "running", startedAt: "2026-11-17T11:05:00Z")
        XCTAssertEqual(fresh.runningWords(now: now), "Just started")
        XCTAssertEqual(RunningTask(id: "d", label: "x", state: "running").runningWords(now: now), "Running")
    }
}
