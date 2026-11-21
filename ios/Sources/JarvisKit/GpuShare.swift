// Who is using the graphics card right now (Dylan, 2026-11-18: "can we have
// a pie chart of instantaneous use of gpu and who's using it?"). The home
// page snapshot has the card's memory in use and total (metrics, id "gpu",
// from nvidia-smi) and each model Ollama has loaded with its memory
// (models[].vramGb). Under WSL nvidia-smi can't name processes, so whatever
// is in use beyond Ollama's models is one "Speech & voice" slice (Parakeet
// and the voice live there). The rest is free. A newer snapshot names every
// holder itself (`gpu`: {totalMb, usedMb, utilization, users}); when that's
// there it wins, and the guess above is only the fallback.
import Foundation

/// One of the snapshot's gauges (memory, GPU memory, processor, disk).
public struct Metric: Decodable, Equatable, Sendable {
    public let id: String
    public let value: Double?
    public let total: Double?
    /// The last samples, oldest first (the server keeps 24).
    public let history: [Double]?

    enum CodingKeys: String, CodingKey { case id, value, total, history }

    public init(id: String, value: Double?, total: Double?, history: [Double]? = nil) {
        self.id = id; self.value = value; self.total = total; self.history = history
    }

    /// A bad history (a null sample) is dropped, not fatal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? nil
        total = (try? c.decodeIfPresent(Double.self, forKey: .total)) ?? nil
        history = ((try? c.decodeIfPresent([Double?].self, forKey: .history)) ?? nil)?.compactMap { $0 }
    }
}

/// One model Ollama has loaded.
public struct LoadedModel: Decodable, Equatable, Sendable {
    public let name: String
    /// chat, watch or other.
    public let role: String?
    public let vramGb: Double?
}

/// Something holding GPU memory that Jarvis names itself (Parakeet, the
/// voice); not sent yet, read when it is.
public struct GpuUser: Decodable, Equatable, Sendable {
    public let name: String
    public let vramGb: Double?
}

/// The snapshot's own account of the card (newer servers): totals, how
/// busy it is, and who holds what. Every field optional.
public struct GpuReading: Decodable, Equatable, Sendable {
    public struct User: Decodable, Equatable, Sendable {
        public let name: String?
        public let role: String?
        public let mb: Double?
        /// local (an Ollama model), speech (one of Jarvis's own), other.
        public let kind: String?
    }
    public let totalMb: Double?
    public let usedMb: Double?
    /// How busy the card is, 0...100.
    public let utilization: Double?
    public let users: [User]?

    enum CodingKeys: String, CodingKey { case totalMb, usedMb, utilization, users }

    /// Reads what's there; a bad user row is skipped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalMb = (try? c.decodeIfPresent(Double.self, forKey: .totalMb)) ?? nil
        usedMb = (try? c.decodeIfPresent(Double.self, forKey: .usedMb)) ?? nil
        utilization = (try? c.decodeIfPresent(Double.self, forKey: .utilization)) ?? nil
        users = ((try? c.decodeIfPresent([Maybe].self, forKey: .users)) ?? nil)?.compactMap(\.user)
    }

    private struct Maybe: Decodable {
        let user: User?
        init(from decoder: Decoder) throws { user = try? User(from: decoder) }
    }
}

/// A slice of the pie.
public struct GpuSlice: Equatable, Sendable, Identifiable {
    /// The colour family: local models, Jarvis's speech models, the rest, free.
    public enum Kind: Equatable, Sendable { case local, speech, other, free }
    public let name: String
    /// A few plain words: "Local brain", "Hears you"; nil when unknown.
    public let role: String?
    public let gb: Double
    public let kind: Kind
    public var id: String { name }

    public init(name: String, role: String? = nil, gb: Double, kind: Kind) {
        self.name = name; self.role = role; self.gb = gb; self.kind = kind
    }

    /// "6.4 GB".
    public var sizeText: String { String(format: "%.1f GB", gb) }
}

/// The pie: slices biggest first (free last), and the card's totals.
public struct GpuShare: Equatable, Sendable {
    public let slices: [GpuSlice]
    public let usedGb: Double
    public let totalGb: Double
    /// How busy the card is, 0...100, when known.
    public var utilization: Double? = nil

    /// Slices smaller than this are folded into "Other", so the pie stays readable.
    public static let smallestSlice = 0.1

    /// The pie from the card's use and what's named on it; nil without a
    /// readable GPU reading.
    public static func from(usedGb: Double?, totalGb: Double?, models: [LoadedModel], users: [GpuUser] = []) -> GpuShare? {
        guard let used = usedGb, let total = totalGb, total > 0, used >= 0 else { return nil }
        let usedClamped = min(used, total)
        var slices: [GpuSlice] = []
        for model in models {
            guard let gb = model.vramGb, gb >= smallestSlice else { continue }
            slices.append(GpuSlice(name: ModelWording.gpuName(model.name), role: model.role == "chat" || model.role == "watch" ? "Local brain" : nil, gb: gb, kind: .local))
        }
        for user in users {
            guard let gb = user.vramGb, gb >= smallestSlice else { continue }
            slices.append(GpuSlice(name: user.name, gb: gb, kind: .other))
        }
        // Named slices can't add up to more than is in use (the readings
        // come a moment apart): scale them down if they do.
        let named = slices.reduce(0) { $0 + $1.gb }
        if named > usedClamped, named > 0 {
            let scale = usedClamped / named
            slices = slices.map { GpuSlice(name: $0.name, role: $0.role, gb: $0.gb * scale, kind: $0.kind) }
        }
        let rest = usedClamped - min(named, usedClamped)
        if rest >= smallestSlice {
            // With Jarvis naming his own holders the rest is just "Other".
            slices.append(GpuSlice(name: users.isEmpty ? "Speech & voice" : "Other", role: users.isEmpty ? "Probably hearing and voice" : nil, gb: rest, kind: users.isEmpty ? .speech : .other))
        }
        slices.sort { $0.gb > $1.gb }
        let free = total - usedClamped
        if free >= smallestSlice { slices.append(GpuSlice(name: "Free", gb: free, kind: .free)) }
        return GpuShare(slices: slices, usedGb: usedClamped, totalGb: total)
    }

    /// The pie from the snapshot's own `gpu` reading: its users as they
    /// come (they're named and sized already), Free as the rest. Nil
    /// without readable totals, so the guess can take over.
    public static func from(_ reading: GpuReading) -> GpuShare? {
        guard let totalMb = reading.totalMb, totalMb > 0, let usedMb = reading.usedMb, usedMb >= 0 else { return nil }
        let used = min(usedMb, totalMb) / 1024
        let total = totalMb / 1024
        var slices: [GpuSlice] = (reading.users ?? []).compactMap { user in
            guard let mb = user.mb, mb / 1024 >= smallestSlice else { return nil }
            let kind: GpuSlice.Kind
            switch user.kind {
            case "local": kind = .local
            case "speech": kind = .speech
            default: kind = .other
            }
            let name = (user.name?.isEmpty == false ? user.name : nil) ?? "Everything else"
            return GpuSlice(name: name, role: user.role, gb: mb / 1024, kind: kind)
        }
        slices.sort { $0.gb > $1.gb }
        let free = total - used
        if free >= smallestSlice { slices.append(GpuSlice(name: "Free", gb: free, kind: .free)) }
        var share = GpuShare(slices: slices, usedGb: used, totalGb: total)
        share.utilization = reading.utilization.map { min(100, max(0, $0)) }
        return share
    }

    /// Which shade of its kind's colour a slice takes: 0 for the first of
    /// that kind, 1 for the next…, so two speech models look related but
    /// distinct.
    public func shade(of slice: GpuSlice) -> Int {
        slices.filter { $0.kind == slice.kind }.firstIndex { $0.id == slice.id } ?? 0
    }

    /// "10.8 of 12 GB in use".
    public var summary: String {
        let total = totalGb == totalGb.rounded() ? String(Int(totalGb)) : String(format: "%.1f", totalGb)
        var line = String(format: "%.1f of %@ GB in use", usedGb, total)
        if let utilization { line += " · \(Int(utilization.rounded()))% busy" }
        return line
    }
}

extension ModelWording {
    /// A model's name for the pie: "ornith-1.5:9b" → "Ornith", "qwen3:8b" → "Qwen3".
    public static func gpuName(_ model: String) -> String {
        let base = model.split(separator: ":").first.map(String.init) ?? model
        let word = base.split(separator: "-").first.map(String.init) ?? base
        guard let first = word.first else { return model }
        return first.uppercased() + word.dropFirst()
    }
}
