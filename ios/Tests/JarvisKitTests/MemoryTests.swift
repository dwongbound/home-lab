import XCTest
@testable import JarvisKit

final class MemoryTests: XCTestCase {
    func testGraphAndNodeDecode() throws {
        let graph = try JSONDecoder().decode(MemoryGraph.self, from: Data(#"{"nodes":[{"id":"dylan","type":"person","name":"Dylan","group":"","facts":3,"links":1,"updated":""},{"id":"people/sam","type":"person","name":"Sam","facts":1,"links":1}],"links":[{"from":"people/sam","to":"dylan","kind":"knows"}]}"#.utf8))
        XCTAssertEqual(graph.nodes.count, 2)
        let node = try JSONDecoder().decode(MemoryNode.self, from: Data(#"{"id":"dylan","type":"person","name":"Dylan","facts":[{"id":"f1","text":"Up late","source":"chat"}],"links":[{"id":"people/sam","name":"Sam","type":"person","kind":"knows"}]}"#.utf8))
        XCTAssertEqual(node.facts.first?.text, "Up late")
        XCTAssertTrue(node.loops.isEmpty)
    }

    func testLayoutCentresDylanAndKeepsInside() {
        let graph = MemoryGraph(nodes: [.init(id: "dylan", type: "person", name: "Dylan"), .init(id: "a", type: "place", name: "A"), .init(id: "b", type: "plan", name: "B")], links: [.init(from: "dylan", to: "a"), .init(from: "dylan", to: "b")])
        let spots = MemoryLayout.place(graph, side: 400)
        XCTAssertEqual(spots.count, 3)
        for spot in spots.values { XCTAssertTrue((0...400).contains(spot.x) && (0...400).contains(spot.y)) }
        XCTAssertEqual(spots["dylan"]!.x, 200, accuracy: 60)
    }

    func testNodeIdIsOneEncodedPiece() {
        let url = JarvisClient(base: URL(string: "https://x.example")!).memoryNodeRequest("loops/priya flight").url!.absoluteString
        XCTAssertEqual(url, "https://x.example/api/jarvis/memory/node/loops%2Fpriya%20flight")
    }
}
