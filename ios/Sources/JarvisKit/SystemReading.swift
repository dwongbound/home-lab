// The PC at a glance (Dylan, 2026-11-21: "is the gpu usage information
// live on my homescreen? can we add the same for RAM? … also add disk
// storage. and i like these graphs and stuff vs words"). Home's System
// panel, its drawer and the TV / kiosk slide all draw from here:
//
// - `metrics` (every server): value, total and the last 24 samples of
//   RAM, GPU memory, CPU and disk. Note the disk gauge is FREE space, so
//   it's turned round into used here.
// - `ram` and `disks` (newer servers, null until then): who holds memory
//   and which folders fill each disk, biggest first, each with an
//   "Everything else" row. Read leniently: a bad row is skipped, and with
//   neither the breakdown is simply left out.
import Foundation

/// The snapshot's `ram`: the memory and who holds it.
public struct RamReading: Decodable, Equatable, Sendable {
    public struct User: Decodable, Equatable, Sendable {
        public let name: String
        public let role: String?
        public let mb: Double
    }
    public let totalMb: Double?
    public let usedMb: Double?
    /// "pc" (the whole computer) or "linux" (only the WSL side).
    public let scope: String?
    public let users: [User]

    enum CodingKeys: String, CodingKey { case totalMb, usedMb, scope, users }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalMb = (try? c.decodeIfPresent(Double.self, forKey: .totalMb)) ?? nil
        usedMb = (try? c.decodeIfPresent(Double.self, forKey: .usedMb)) ?? nil
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? nil
        users = (((try? c.decodeIfPresent([LenientRow<User>].self, forKey: .users)) ?? nil) ?? []).compactMap(\.value)
    }

    /// "Whole PC" or "Linux side only", nil when not said.
    public var scopeWords: String? {
        switch scope {
        case "pc": return "Whole PC"
        case "linux": return "Linux side only"
        default: return nil
        }
    }
}

/// One of the snapshot's `disks`, with its biggest folders.
public struct DiskReading: Decodable, Equatable, Sendable, Identifiable {
    public struct User: Decodable, Equatable, Sendable {
        public let name: String
        public let gb: Double
    }
    public let id: String
    public let name: String
    public let usedGb: Double
    public let totalGb: Double
    public let users: [User]

    enum CodingKeys: String, CodingKey { case id, name, usedGb, totalGb, users }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? id
        usedGb = try c.decode(Double.self, forKey: .usedGb)
        totalGb = try c.decode(Double.self, forKey: .totalGb)
        users = (((try? c.decodeIfPresent([LenientRow<User>].self, forKey: .users)) ?? nil) ?? []).compactMap(\.value)
    }
}

/// A row that may or may not decode; a bad one is skipped.
struct LenientRow<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// One gauge on the System panel: how full, the number, and its recent
/// history as fractions of the total (oldest first).
public struct SystemGauge: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case gpu, ram, disk, cpu }
    public let kind: Kind
    public let used: Double
    public let total: Double
    /// GB, or % for the processor.
    public let unit: String
    public let history: [Double]
    /// Memory the system gives back when needed (part of `used`).
    public var reclaimable: Double = 0
    public var id: String { kind.rawValue }

    public init(kind: Kind, used: Double, total: Double, unit: String, history: [Double], reclaimable: Double = 0) {
        self.kind = kind; self.used = used; self.total = total; self.unit = unit; self.history = history; self.reclaimable = reclaimable
    }

    public var fraction: Double { total > 0 ? min(1, max(0, used / total)) : 0 }

    public var title: String {
        switch kind {
        case .gpu: return "GPU"
        case .ram: return "Memory"
        case .disk: return "Disk"
        case .cpu: return "CPU"
        }
    }

    public var symbol: String {
        switch kind {
        case .gpu: return "cpu"
        case .ram: return "memorychip"
        case .disk: return "internaldrive"
        case .cpu: return "gauge.with.dots.needle.33percent"
        }
    }

    /// The big number in the ring: "84%".
    public var percentText: String { "\(Int((fraction * 100).rounded()))%" }

    /// "10.1 of 12 GB", or "18% busy" for the processor.
    public var amountText: String {
        if kind == .cpu { return "\(Int(used.rounded()))% busy" }
        return "\(SystemGauge.number(used)) of \(SystemGauge.number(total)) GB"
    }

    /// "Free 1.9 GB".
    public var freeText: String? {
        guard kind != .cpu else { return nil }
        let free = "\(SystemGauge.number(max(0, total - used))) GB free"
        return reclaimable >= 0.1 ? free + " + \(SystemGauge.number(reclaimable)) GB reclaimable" : free
    }

    /// 10.1 → "10.1", 237 → "237", 12.0 → "12".
    public static func number(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}

/// One coloured part of a breakdown bar.
public struct SystemSlice: Equatable, Sendable, Identifiable {
    public let name: String
    public let role: String?
    public let gb: Double
    /// Free space: drawn faint, always last.
    public let isFree: Bool
    public var id: String { name + (isFree ? "#free" : "") }

    /// Memory the system gives back when it's needed (Linux's file
    /// cache): drawn lighter, so it doesn't make memory look full.
    public var isReclaimable: Bool {
        let n = name.lowercased()
        return !isFree && (n.contains("file cache") || n == "cache" || n.hasSuffix(" cache"))
    }

    public init(name: String, role: String? = nil, gb: Double, isFree: Bool = false) {
        self.name = name; self.role = role; self.gb = gb; self.isFree = isFree
    }

    /// "168 GB", "9.2 GB", "370 MB" (a 41 MB row isn't "0.0 GB").
    public var sizeText: String {
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb < 0.95 { return "\(Int((gb * 1024).rounded())) MB" }
        return String(format: "%.1f GB", gb)
    }
}

/// A breakdown: who holds what, then Free.
public struct SystemBreakdown: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// A small plain label: "Whole PC", "Folders measured about hourly".
    public let note: String?
    public let slices: [SystemSlice]
    public let usedGb: Double
    public let totalGb: Double
    /// A disk that grows as it fills (the Linux disk): the size it may
    /// grow to, said in small words, the bar drawn over what's used.
    public var growsToGb: Double? = nil

    public init(id: String, title: String, note: String?, slices: [SystemSlice], usedGb: Double, totalGb: Double, growsToGb: Double? = nil) {
        self.id = id; self.title = title; self.note = note; self.slices = slices; self.usedGb = usedGb; self.totalGb = totalGb; self.growsToGb = growsToGb
    }

    /// What the bar is measured against: the total, or what's used on a
    /// growing disk.
    public var barTotal: Double { growsToGb == nil ? totalGb : max(usedGb, 0.001) }

    /// Slices big enough to see in the bar (the rest are in the legend).
    public var barSlices: [SystemSlice] {
        slices.filter { $0.gb / max(barTotal, 0.001) >= 0.004 }
    }

    /// Reclaimable memory, in GB.
    public var reclaimableGb: Double { slices.filter(\.isReclaimable).reduce(0) { $0 + $1.gb } }

    /// The heading line: "C: drive · 233 of 255 GB", or "Linux disk · 52 GB used".
    public var headline: String {
        if growsToGb != nil { return "\(title) · \(SystemGauge.number(usedGb)) GB used" }
        return "\(title) · \(SystemGauge.number(usedGb)) of \(SystemGauge.number(totalGb)) GB"
    }

    /// Stable colour slots by NAME (the same name, the same colour on Home,
    /// in the drawer and on the TV), never two alike in one breakdown.
    /// nil for free space and "Everything else".
    public func colorSlot(_ slice: SystemSlice, slots: Int) -> Int? {
        guard !slice.isFree, !SystemBreakdown.isRest(slice.name), slots > 0 else { return nil }
        var taken = Set<Int>()
        var mine: Int?
        for name in slices.filter({ !$0.isFree && !SystemBreakdown.isRest($0.name) }).map(\.name).sorted() {
            var slot = SystemBreakdown.hash(name) % slots
            var tries = 0
            while taken.contains(slot), tries < slots { slot = (slot + 1) % slots; tries += 1 }
            taken.insert(slot)
            if name == slice.name { mine = slot }
        }
        return mine
    }

    public static func isRest(_ name: String) -> Bool { name == "Everything else" || name == "Other" }

    static func hash(_ name: String) -> Int {
        var h: UInt32 = 5381
        for b in name.lowercased().utf8 { h = (h &* 33) &+ UInt32(b) }
        return Int(h % 10_007)
    }
}

extension Snapshot {
    /// The gauges with readable numbers: GPU, memory, disk, then CPU.
    public var systemGauges: [SystemGauge] {
        var out: [SystemGauge] = []
        func metric(_ id: String) -> Metric? { metrics.first { $0.id == id } }

        if let share = gpuShare {
            let m = metric("gpu")
            out.append(SystemGauge(kind: .gpu, used: share.usedGb, total: share.totalGb, unit: "GB",
                                   history: SystemGauge.fractions(m?.history ?? [], total: m?.total ?? share.totalGb)))
        }
        let ramMetric = metric("ram")
        if let ram, let used = ram.usedMb, let total = ram.totalMb, total > 0 {
            out.append(SystemGauge(kind: .ram, used: used / 1024, total: total / 1024, unit: "GB",
                                   history: SystemGauge.fractions(ramMetric?.history ?? [], total: ramMetric?.total ?? total / 1024),
                                   reclaimable: ramBreakdown?.reclaimableGb ?? 0))
        } else if let m = ramMetric, let used = m.value, let total = m.total, total > 0 {
            out.append(SystemGauge(kind: .ram, used: used, total: total, unit: "GB", history: SystemGauge.fractions(m.history ?? [], total: total)))
        }
        // The disk gauge is free space; the panel shows it full, like the others.
        let diskMetric = metric("disk")
        let diskHistory = diskMetric.flatMap { m in m.total.map { t in (m.history ?? []).map { t - $0 } } } ?? []
        if let c = disks?.first(where: { $0.id == "c" }) ?? disks?.first, c.totalGb > 0 {
            out.append(SystemGauge(kind: .disk, used: c.usedGb, total: c.totalGb, unit: "GB",
                                   history: SystemGauge.fractions(diskHistory, total: diskMetric?.total ?? c.totalGb)))
        } else if let m = diskMetric, let free = m.value, let total = m.total, total > 0 {
            out.append(SystemGauge(kind: .disk, used: max(0, total - free), total: total, unit: "GB", history: SystemGauge.fractions(diskHistory, total: total)))
        }
        if let m = metric("cpu"), let value = m.value {
            out.append(SystemGauge(kind: .cpu, used: value, total: 100, unit: "%", history: SystemGauge.fractions(m.history ?? [], total: 100)))
        }
        return out
    }

    /// Who holds memory, when Jarvis says (`ram.users`); nil otherwise.
    public var ramBreakdown: SystemBreakdown? {
        guard let ram, let used = ram.usedMb, let total = ram.totalMb, total > 0, !ram.users.isEmpty else { return nil }
        var slices = ram.users.filter { $0.mb > 0 }.map {
            SystemSlice(name: $0.name, role: ($0.role?.isEmpty ?? true) ? nil : $0.role, gb: $0.mb / 1024)
        }
        let free = (total - min(used, total)) / 1024
        if free > 0.05 { slices.append(SystemSlice(name: "Free", gb: free, isFree: true)) }
        return SystemBreakdown(id: "ram", title: "Memory", note: ram.scopeWords, slices: slices, usedGb: min(used, total) / 1024, totalGb: total / 1024)
    }

    /// Each disk with its biggest folders (`disks`); empty without them.
    public var diskBreakdowns: [SystemBreakdown] {
        (disks ?? []).filter { $0.totalGb > 0 }.map { disk in
            var slices = disk.users.filter { $0.gb > 0 }.map { SystemSlice(name: $0.name, gb: $0.gb) }
            let named = slices.filter { !SystemBreakdown.isRest($0.name) }
            if named.isEmpty { slices = [SystemSlice(name: "Used", gb: min(disk.usedGb, disk.totalGb))] }
            // The Linux disk's total is what it may grow to: a ring of 52 of
            // 1081 GB reads empty, so it's measured by what's used.
            let grows = disk.id == "linux"
            let free = disk.totalGb - min(disk.usedGb, disk.totalGb)
            if !grows, free > 0.05 { slices.append(SystemSlice(name: "Free", gb: free, isFree: true)) }
            return SystemBreakdown(id: "disk-\(disk.id)", title: disk.name,
                                   note: named.isEmpty ? nil : "Folders measured about hourly",
                                   slices: slices, usedGb: min(disk.usedGb, disk.totalGb), totalGb: disk.totalGb,
                                   growsToGb: grows ? disk.totalGb : nil)
        }
    }
}

extension SystemGauge {
    /// Samples as fractions of the total, clamped to 0...1.
    static func fractions(_ values: [Double], total: Double) -> [Double] {
        guard total > 0 else { return [] }
        return values.map { min(1, max(0, $0 / total)) }
    }
}

extension GpuShare {
    /// The card as a breakdown, the same shape as memory and disks.
    public var breakdown: SystemBreakdown {
        SystemBreakdown(id: "gpu", title: "Graphics card",
                        note: utilization.map { "\(Int($0.rounded()))% busy" },
                        slices: slices.map { SystemSlice(name: $0.name, role: $0.role, gb: $0.gb, isFree: $0.kind == .free) },
                        usedGb: usedGb, totalGb: totalGb)
    }
}

extension Snapshot {
    /// The breakdown that colours a gauge's ring, when there is one.
    public func breakdown(for kind: SystemGauge.Kind) -> SystemBreakdown? {
        switch kind {
        case .gpu: return gpuShare?.breakdown
        case .ram: return ramBreakdown
        case .disk: return diskBreakdowns.first { $0.id == "disk-c" } ?? diskBreakdowns.first
        case .cpu: return nil
        }
    }
}

/// "Checked 10:34 AM" on the System panel (Dylan, 2026-11-21: "can we add a
/// last checked (time)? so i know"): when the PC was read, from the
/// snapshot's own `generatedAt`, not the phone's clock. Over a minute old
/// (Jarvis or Tailscale unreachable) it says how old, and is stale.
public enum SystemChecked {
    public static let staleAfter: TimeInterval = 60

    public static func words(generatedAt: String, now: Date = Date()) -> (text: String, stale: Bool)? {
        guard let at = AgendaTime.parse(generatedAt) else { return nil }
        let age = now.timeIntervalSince(at)
        guard age > staleAfter else {
            return ("Checked \(at.formatted(date: .omitted, time: .shortened))", false)
        }
        let minutes = Int(age / 60)
        if minutes < 60 { return ("Checked \(minutes) min ago", true) }
        let hours = minutes / 60
        if hours < 24 { return ("Checked \(hours) h ago", true) }
        return ("Checked \(at.formatted(date: .abbreviated, time: .shortened))", true)
    }
}
