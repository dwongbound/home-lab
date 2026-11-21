import XCTest
@testable import JarvisKit

final class SystemReadingTests: XCTestCase {
    private func snapshot(_ extra: String) throws -> Snapshot {
        let json = #"{"generatedAt":"x","today":[],"services":[],"# + extra + "}"
        return try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    /// Today's server: only `metrics`. Disk comes as FREE space and is
    /// turned round into used; no breakdowns.
    func testMetricsAloneGiveFourGauges() throws {
        let s = try snapshot(#""metrics":[{"id":"ram","value":11.4,"total":16,"history":[8,16]},{"id":"gpu","value":10.1,"total":12},{"id":"cpu","value":18,"total":100,"history":[50,null,25]},{"id":"disk","value":93,"total":237,"history":[95,93]}]"#)
        XCTAssertEqual(s.systemGauges.map(\.kind), [.gpu, .ram, .disk, .cpu])
        let disk = try XCTUnwrap(s.systemGauges.first { $0.kind == .disk })
        XCTAssertEqual(disk.used, 144)
        XCTAssertEqual(disk.history.count, 2)
        XCTAssertEqual(disk.history[1], 144.0 / 237, accuracy: 0.001)
        let ram = try XCTUnwrap(s.systemGauges.first { $0.kind == .ram })
        XCTAssertEqual(ram.history, [0.5, 1])
        XCTAssertEqual(ram.amountText, "11.4 of 16 GB")
        XCTAssertEqual(s.systemGauges.last?.history, [0.5, 0.25], "a null sample is dropped")
        XCTAssertEqual(s.systemGauges.last?.amountText, "18% busy")
        XCTAssertNil(s.ramBreakdown)
        XCTAssertTrue(s.diskBreakdowns.isEmpty)
    }

    func testNoMetricsNoGauges() throws {
        XCTAssertTrue(try snapshot(#""metrics":[]"#).systemGauges.isEmpty)
    }

    /// The newer shapes: users biggest first, Free last, scope in words.
    func testBreakdownsWhenPresent() throws {
        let s = try snapshot(#""ram":{"totalMb":32768,"usedMb":20480,"scope":"pc","users":[{"name":"Ollama","role":"Local models","mb":8192},{"name":"Everything else","role":"","mb":12288},{"name":"Bad","mb":"lots"}]},"disks":[{"id":"c","name":"C: drive","usedGb":144,"totalGb":237,"users":[{"name":"Models","gb":58},{"name":"Everything else","gb":86}]},{"id":"linux","name":"Linux disk","usedGb":61,"totalGb":250},{"id":"broken"}]"#)
        let ram = try XCTUnwrap(s.ramBreakdown)
        XCTAssertEqual(ram.note, "Whole PC")
        XCTAssertEqual(ram.slices.map(\.name), ["Ollama", "Everything else", "Free"])
        XCTAssertNil(ram.slices[1].role, "an empty role reads as none")
        XCTAssertEqual(ram.slices.last?.gb ?? 0, 12, accuracy: 0.01)
        XCTAssertEqual(s.diskBreakdowns.map(\.title), ["C: drive", "Linux disk"], "a broken disk is skipped")
        XCTAssertEqual(s.diskBreakdowns[0].note, "Folders measured about hourly")
        XCTAssertEqual(s.diskBreakdowns[1].slices.map(\.name), ["Used"], "no folders yet: used (a growing Linux disk has no Free)")
        // The gauges prefer the named readings.
        XCTAssertEqual(s.systemGauges.first { $0.kind == .ram }?.total, 32)
        XCTAssertEqual(s.systemGauges.first { $0.kind == .disk }?.used, 144)
    }

    func testLinuxScopeWords() throws {
        let s = try snapshot(#""ram":{"totalMb":16000,"usedMb":8000,"scope":"linux","users":[{"name":"Jarvis","mb":2000}]}"#)
        XCTAssertEqual(s.ramBreakdown?.note, "Linux side only")
    }

    func testNumbers() {
        XCTAssertEqual(SystemGauge.number(12), "12")
        XCTAssertEqual(SystemGauge.number(10.14), "10.1")
        XCTAssertEqual(SystemGauge.number(237.4), "237")
    }

    func testDemoHasEverything() throws {
        let s = try XCTUnwrap(DemoSnapshot.build(now: Date(), sparse: false))
        XCTAssertEqual(s.systemGauges.count, 4)
        XCTAssertNotNil(s.ramBreakdown)
        XCTAssertEqual(s.diskBreakdowns.count, 3)
    }

    /// Linux's file cache is drawn as reclaimable and said in words.
    func testFileCacheIsReclaimable() throws {
        let s = try XCTUnwrap(DemoSnapshot.build(now: Date(), sparse: false))
        let ram = try XCTUnwrap(s.ramBreakdown)
        XCTAssertTrue(ram.slices[0].isReclaimable)
        XCTAssertFalse(ram.slices[1].isReclaimable)
        let gauge = try XCTUnwrap(s.systemGauges.first { $0.kind == .ram })
        XCTAssertTrue(gauge.freeText?.contains("reclaimable") ?? false)
        // Tiny rows stay in the legend but not the bar.
        XCTAssertTrue(ram.slices.contains { $0.name == "Everything else" })
        XCTAssertFalse(ram.barSlices.contains { $0.name == "Everything else" })
    }

    /// The Linux disk is measured by what's used; an empty folder list
    /// is just used and free; C: heads the panel.
    func testDisks() throws {
        let s = try XCTUnwrap(DemoSnapshot.build(now: Date(), sparse: false))
        let linux = try XCTUnwrap(s.diskBreakdowns.first { $0.id == "disk-linux" })
        XCTAssertEqual(linux.growsToGb, 1081)
        XCTAssertFalse(linux.slices.contains(where: \.isFree))
        XCTAssertEqual(linux.headline, "Linux disk · 54 GB used")
        let d = try XCTUnwrap(s.diskBreakdowns.first { $0.id == "disk-d" })
        XCTAssertEqual(d.slices.map(\.name), ["Used", "Free"])
        XCTAssertNil(d.note)
        XCTAssertEqual(s.systemGauges.first { $0.kind == .disk }?.used, 231)
    }

    /// The same name gets the same colour whatever the order, and no two
    /// names in one breakdown share one (up to the palette's 12).
    func testColoursByName() throws {
        let s = try XCTUnwrap(DemoSnapshot.build(now: Date(), sparse: false))
        let ram = try XCTUnwrap(s.ramBreakdown)
        let slots = ram.slices.compactMap { ram.colorSlot($0, slots: 12) }
        XCTAssertEqual(Set(slots).count, slots.count)
        let reordered = SystemBreakdown(id: "ram", title: "", note: nil, slices: ram.slices.reversed(), usedGb: ram.usedGb, totalGb: ram.totalGb)
        for slice in ram.slices { XCTAssertEqual(ram.colorSlot(slice, slots: 12), reordered.colorSlot(slice, slots: 12)) }
        XCTAssertNil(ram.colorSlot(ram.slices.first { $0.name == "Everything else" }!, slots: 12))
    }

    /// Null on a server failure: the gauges still come from metrics.
    func testNullBreakdowns() throws {
        let s = try snapshot(#""ram":null,"disks":null,"metrics":[{"id":"ram","value":20,"total":32},{"id":"disk","value":24,"total":255}]"#)
        XCTAssertNil(s.ramBreakdown)
        XCTAssertTrue(s.diskBreakdowns.isEmpty)
        XCTAssertEqual(s.systemGauges.map(\.kind), [.ram, .disk])
        XCTAssertEqual(s.systemGauges.last?.used, 231)
    }
}
