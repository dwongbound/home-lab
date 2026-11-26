// Jarvis's memory as a web (Dylan, 2026-11-26): the things he knows about
// (people, places, projects…) as bubbles, the links between them as lines,
// and one bubble's facts on a tap. Server: GET /api/jarvis/memory/graph and
// /api/jarvis/memory/node/<id> (server/sources/memory-graph.mjs).
import Foundation

public struct MemoryGraph: Decodable, Equatable, Sendable {
    public struct Node: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let type: String
        public let name: String
        /// How many facts and links it has (counts, not the facts themselves).
        public let facts: Int
        public let links: Int
        public init(id: String, type: String, name: String, facts: Int = 0, links: Int = 0) {
            self.id = id; self.type = type; self.name = name; self.facts = facts; self.links = links
        }
    }
    /// Reads from → to: "girlfriend of" means `from` is the girlfriend of `to`.
    public struct Link: Decodable, Equatable, Sendable {
        public let from: String
        public let to: String
        public let kind: String?
        public init(from: String, to: String, kind: String? = nil) { self.from = from; self.to = to; self.kind = kind }
    }
    public let nodes: [Node]
    public let links: [Link]
    public init(nodes: [Node], links: [Link]) { self.nodes = nodes; self.links = links }
}

/// One bubble opened: its facts, what it links to, and open loops.
public struct MemoryNode: Decodable, Equatable, Sendable {
    public struct Fact: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let text: String
    }
    public struct Neighbour: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let type: String?
        public let kind: String?
    }
    public struct Loop: Decodable, Equatable, Sendable {
        public let text: String
        public let due: String?
    }
    public let id: String
    public let type: String
    public let name: String
    public let facts: [Fact]
    public let links: [Neighbour]
    public let loops: [Loop]

    enum CodingKeys: String, CodingKey { case id, type, name, facts, links, loops }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = (try? c.decode(String.self, forKey: .type)) ?? "other"
        name = try c.decode(String.self, forKey: .name)
        facts = (try? c.decode([Fact].self, forKey: .facts)) ?? []
        links = (try? c.decode([Neighbour].self, forKey: .links)) ?? []
        loops = (try? c.decode([Loop].self, forKey: .loops)) ?? []
    }
}

/// Where each bubble sits: a plain spring layout run once (links pull,
/// bubbles push apart, a soft pull to the middle). Deterministic, so the
/// web looks the same each time it opens.
public enum MemoryLayout {
    /// Points in a square of `side`, Dylan's own node ("dylan") in the middle.
    public static func place(_ graph: MemoryGraph, side: Double, steps: Int = 300) -> [String: (x: Double, y: Double)] {
        let ids = graph.nodes.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var x = ids.indices.map { cos(Double($0)) * side * 0.3 }
        var y = ids.indices.map { sin(Double($0)) * side * 0.3 }
        if let me = index["dylan"] { x[me] = 0; y[me] = 0 }
        let pairs = graph.links.compactMap { link -> (Int, Int)? in
            guard let a = index[link.from], let b = index[link.to], a != b else { return nil }
            return (a, b)
        }
        let spacing = side / max(4, Double(ids.count).squareRoot() * 1.6)
        for step in 0..<steps {
            let heat = 1 - Double(step) / Double(steps)
            var dx = [Double](repeating: 0, count: ids.count)
            var dy = dx
            for i in ids.indices {
                for j in ids.indices where i != j {
                    let ex = x[i] - x[j], ey = y[i] - y[j]
                    let d2 = max(1, ex * ex + ey * ey)
                    let push = spacing * spacing / d2
                    dx[i] += ex * push * 0.05
                    dy[i] += ey * push * 0.05
                }
                dx[i] -= x[i] * 0.01
                dy[i] -= y[i] * 0.01
            }
            for (a, b) in pairs {
                let ex = x[b] - x[a], ey = y[b] - y[a]
                let d = max(1, (ex * ex + ey * ey).squareRoot())
                let pull = (d - spacing) / d * 0.05
                dx[a] += ex * pull; dy[a] += ey * pull
                dx[b] -= ex * pull; dy[b] -= ey * pull
            }
            for i in ids.indices {
                x[i] = max(-side / 2, min(side / 2, x[i] + max(-20, min(20, dx[i])) * heat))
                y[i] = max(-side / 2, min(side / 2, y[i] + max(-20, min(20, dy[i])) * heat))
            }
        }
        var out: [String: (x: Double, y: Double)] = [:]
        for (i, id) in ids.enumerated() { out[id] = (x[i] + side / 2, y[i] + side / 2) }
        return out
    }
}

extension JarvisClient {
    /// The whole web, or nil from a Jarvis that doesn't have one yet.
    public func memoryGraph() async throws -> MemoryGraph? {
        struct Answer: Decodable { let graph: MemoryGraph? }
        let data = try await send(request("api/jarvis/memory/graph"))
        return try JSONDecoder().decode(Answer.self, from: data).graph
    }

    /// The request for one bubble. Ids are Jarvis's own paths ("people/calla"),
    /// so the whole id is one percent-encoded path piece.
    public func memoryNodeRequest(_ id: String) -> URLRequest {
        var request = request("api/jarvis/memory/node")
        let piece = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        request.url = URL(string: (request.url?.absoluteString ?? "") + "/" + piece)
        return request
    }

    /// One bubble's facts, links and loops.
    public func memoryNode(_ id: String) async throws -> MemoryNode {
        struct Answer: Decodable { let node: MemoryNode }
        return try JSONDecoder().decode(Answer.self, from: try await send(memoryNodeRequest(id))).node
    }

    /// Jarvis forgets one fact.
    public func forgetFact(_ id: String) async throws {
        _ = try await send(request("api/jarvis/memory", method: "POST", json: ["op": "forget", "id": id]))
    }
}

/// How Jarvis sounds: GET/POST /api/jarvis/voice, sample WAVs.
public struct VoiceSettings: Decodable, Equatable, Sendable {
    public struct Option: Decodable, Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let accent: String
        public let gender: String
        /// "British · man".
        public var kind: String { (accent == "gb" ? "British" : "American") + " · " + (gender == "f" ? "woman" : "man") }
    }
    public struct Blend: Decodable, Equatable, Sendable {
        public let voice2: String
        public let mix: Double
    }
    public var voice: String
    /// 0.7 to 1.4, 1 is normal.
    public var speed: Double
    /// Kept as Jarvis has it; the app doesn't edit blends.
    public let blend: Blend?
    public let voices: [Option]

    /// The body a save sends.
    public var body: [String: Any] {
        var out: [String: Any] = ["voice": voice, "speed": speed]
        if let blend { out["blend"] = ["voice2": blend.voice2, "mix": blend.mix] }
        return out
    }

    /// The sample's query (?voice=&speed=&voice2=&mix=).
    public var sampleQuery: [String: String] {
        var out = ["voice": voice, "speed": String(speed)]
        if let blend { out["voice2"] = blend.voice2; out["mix"] = String(blend.mix) }
        return out
    }
}

extension JarvisClient {
    public func voiceSettings() async throws -> VoiceSettings {
        struct Answer: Decodable { let voice: VoiceSettings }
        return try JSONDecoder().decode(Answer.self, from: try await send(request("api/jarvis/voice"))).voice
    }

    public func saveVoice(_ settings: VoiceSettings) async throws {
        _ = try await send(request("api/jarvis/voice", method: "POST", json: settings.body))
    }

    /// A spoken sample as WAV bytes.
    public func voiceSample(_ settings: VoiceSettings) async throws -> Data {
        try await send(request("api/jarvis/voice/sample", query: settings.sampleQuery))
    }
}
