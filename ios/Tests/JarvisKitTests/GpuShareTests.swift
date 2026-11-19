import XCTest
@testable import JarvisKit

final class GpuShareTests: XCTestCase {
    func testTonightsCard() throws {
        // As the snapshot read at 11:55 PM: 10.8 of 12 GB, Ornith holding 6.4.
        let json = #"{"generatedAt":"x","today":[],"services":[],"metrics":[{"id":"ram","value":3.8,"total":7.8},{"id":"gpu","label":"GPU memory","value":10.8,"unit":"GB","total":12,"history":[10.8]}],"models":[{"name":"ornith-1.5:9b","role":"watch","vramGb":6.4,"until":null}]}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let share = try XCTUnwrap(snapshot.gpuShare)
        XCTAssertEqual(share.slices.map(\.name), ["Ornith", "Speech & voice", "Free"])
        XCTAssertEqual(share.slices[1].gb, 4.4, accuracy: 0.001)
        XCTAssertEqual(share.slices[2].gb, 1.2, accuracy: 0.001)
        XCTAssertEqual(share.summary, "10.8 of 12 GB in use")
    }

    func testNamedHoldersGetTheirOwnSlices() {
        let share = GpuShare.from(usedGb: 11, totalGb: 12, models: [LoadedModel(name: "qwen3:8b", role: "other", vramGb: 5)], users: [GpuUser(name: "Parakeet", vramGb: 2.5), GpuUser(name: "Voice", vramGb: 1)])
        XCTAssertEqual(share?.slices.map(\.name), ["Qwen3", "Parakeet", "Other", "Voice", "Free"])
    }

    func testNamedMoreThanUsedScalesDown() {
        let share = GpuShare.from(usedGb: 6, totalGb: 12, models: [LoadedModel(name: "a:1", role: nil, vramGb: 4), LoadedModel(name: "b:1", role: nil, vramGb: 4)])
        let named = share?.slices.filter { $0.kind == .local }.reduce(0) { $0 + $1.gb } ?? 0
        XCTAssertEqual(named, 6, accuracy: 0.001)
        XCTAssertFalse(share?.slices.contains { $0.kind == .speech } ?? true)
        XCTAssertEqual(share?.slices.first?.kind, .local)
    }

    func testNoReadingNoPie() {
        XCTAssertNil(GpuShare.from(usedGb: nil, totalGb: 12, models: []))
        XCTAssertNil(GpuShare.from(usedGb: 3, totalGb: 0, models: []))
        let idle = GpuShare.from(usedGb: 0.05, totalGb: 12, models: [])
        XCTAssertEqual(idle?.slices.map(\.name), ["Free"])
    }

    func testNames() {
        XCTAssertEqual(ModelWording.gpuName("ornith-1.5:9b"), "Ornith")
        XCTAssertEqual(ModelWording.gpuName("qwen3:8b"), "Qwen3")
    }

    func testTheServersNamedReadingWins() throws {
        let json = #"{"generatedAt":"x","today":[],"services":[],"metrics":[{"id":"gpu","value":10.8,"total":12}],"models":[{"name":"ornith-1.5:9b","vramGb":6.4}],"gpu":{"totalMb":12288,"usedMb":11059,"utilization":37,"users":[{"name":"Ornith","role":"Local brain","mb":6554,"kind":"local"},{"name":"Parakeet","role":"Hears you","mb":2560,"kind":"speech"},{"name":"Kokoro","role":"His voice","mb":1024,"kind":"speech"},{"name":"Everything else","mb":900,"kind":"other"},{"name":"Bad","mb":"lots"}]}}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        let share = try XCTUnwrap(snapshot.gpuShare)
        XCTAssertEqual(share.slices.map(\.name), ["Ornith", "Parakeet", "Kokoro", "Everything else", "Free"])
        XCTAssertEqual(share.slices[1].role, "Hears you")
        XCTAssertEqual(share.slices[1].kind, .speech)
        XCTAssertEqual(share.slices.last?.gb ?? 0, 1.2, accuracy: 0.01)
        XCTAssertEqual(share.utilization, 37)
        XCTAssertTrue(share.summary.hasSuffix("· 37% busy"))
    }

    func testANullOrUnreadableReadingFallsBack() throws {
        for gpu in ["null", #"{"totalMb":null,"usedMb":null,"utilization":null,"users":[]}"#] {
            let json = #"{"generatedAt":"x","today":[],"services":[],"metrics":[{"id":"gpu","value":10.8,"total":12}],"models":[{"name":"ornith-1.5:9b","vramGb":6.4}],"gpu":"# + gpu + "}"
            let share = try XCTUnwrap(try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)).gpuShare)
            XCTAssertEqual(share.slices.map(\.name), ["Ornith", "Speech & voice", "Free"])
        }
    }

    func testTonightsNamedReading() throws {
        // The live figures at 12:05 AM: 11018 of 12288 MB.
        let json = #"{"totalMb":12288,"usedMb":11018,"utilization":0,"users":[{"name":"Ornith","role":"Local brain","mb":6582,"kind":"local"},{"name":"Parakeet","role":"Hears you","mb":2430,"kind":"speech"},{"name":"Everything else","role":"Windows, the desktop and drivers","mb":1440,"kind":"other"},{"name":"Kokoro","role":"Jarvis's voice","mb":562,"kind":"speech"}]}"#
        let reading = try JSONDecoder().decode(GpuReading.self, from: Data(json.utf8))
        let share = try XCTUnwrap(GpuShare.from(reading))
        XCTAssertEqual(share.slices.map(\.name), ["Ornith", "Parakeet", "Everything else", "Kokoro", "Free"])
        XCTAssertEqual(share.shade(of: share.slices[3]), 1, "Kokoro is the second speech model, a different shade")
        XCTAssertEqual(share.usedGb, 11018.0 / 1024, accuracy: 0.001)
        XCTAssertEqual(share.summary, "10.8 of 12 GB in use · 0% busy")
    }
}
