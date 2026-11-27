// Debug-only counters for the Chat scroll-lag work (2026-11-19): how often
// the whole app re-renders and how often a reply's markdown is parsed.
// Logged under the "jarvis.perf" subsystem every 50th count.
import os

#if DEBUG
enum PerfCount {
    private static let log = Logger(subsystem: "jarvis.perf", category: "count")
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    static func bump(_ name: String) {
        let n = (counts[name] ?? 0) + 1
        counts[name] = n
        if n % 10 == 0 { log.notice("\(name, privacy: .public) \(n)") }
    }
}
#endif
