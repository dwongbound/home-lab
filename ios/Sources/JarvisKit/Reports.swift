// Jarvis's reports: HTML pages he writes for long tasks, served by the home
// page at /reports/{id} (Dylan, 2026-11-18). A "Report ready: …" notice
// carries the id, and the chat turn ends with an "Open the report" link to
// the page. The iPhone and iPad read it in the app's own reader (never
// Safari: "the reports should open from within the jarvis app"); the TV and
// Watch have no reader and say to open it on the iPhone. The list and its
// words (size, when it's deleted, the rule and the room used) match the
// page's src/lib/reports.ts; keep them in step.
import Foundation

public enum Reports {
    /// What the TV and Watch say under a report's summary.
    public static let elsewhere = "Open on your iPhone to read the report"

    /// True for a report id: exactly 16 lowercase hex characters. Checked
    /// before any URL is built, so nothing else can be put in the path.
    public static func isId(_ id: String) -> Bool {
        id.count == 16 && id.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// The page for a report on the home page at `base`, or nil for a bad id.
    public static func url(id: String, base: URL = JarvisClient.defaultBase) -> URL? {
        guard isId(id) else { return nil }
        var parts = URLComponents()
        parts.scheme = base.scheme
        parts.host = base.host
        parts.port = base.port
        parts.path = "/reports/\(id)"
        return parts.url
    }

    /// The report a link points at, when it's one of ours: the same host as
    /// `base` and a path of exactly /reports/{id}. Any other link is nil and
    /// opens as links always have.
    public static func id(in link: URL, base: URL = JarvisClient.defaultBase) -> String? {
        guard let host = link.host?.lowercased(), host == base.host?.lowercased() else { return nil }
        guard link.scheme == "https" || link.scheme == base.scheme else { return nil }
        let pieces = link.path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].isEmpty, pieces[1] == "reports" else { return nil }
        let id = String(pieces[2])
        return isId(id) ? id : nil
    }

    /// Where a tapped link goes: our report page (rebuilt from its id, so the
    /// view only ever opens a URL this code made), or nil to open it as now.
    public static func inAppURL(for link: URL, base: URL = JarvisClient.defaultBase) -> URL? {
        id(in: link, base: base).flatMap { url(id: $0, base: base) }
    }
}

/// One report in the snapshot's list.
public struct Report: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    /// When it was made (ISO).
    public let created: String
    /// When Jarvis deletes it (ISO); nil while Keep is on.
    public let expires: String?
    public let kept: Bool
    public let bytes: Int
    /// How long this one is kept: 14, 30 or 90 days, nil when forever. Only
    /// meaningful when `keepDaysKnown` (a newer server sends the field).
    public let keepDays: Int?
    /// True when the server sent keepDays at all (null included).
    public let keepDaysKnown: Bool

    public init(id: String, title: String, summary: String = "", created: String, expires: String?, kept: Bool, bytes: Int, keepDays: Int? = nil, keepDaysKnown: Bool = false) {
        self.id = id; self.title = title; self.summary = summary; self.created = created
        self.expires = kept ? nil : expires; self.kept = kept; self.bytes = bytes
        self.keepDays = keepDays; self.keepDaysKnown = keepDaysKnown
    }

    enum CodingKeys: String, CodingKey { case id, title, summary, created, expires, kept, bytes, keepDays }

    /// Reads one leniently: only the id and title are needed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let kept = (try? c.decodeIfPresent(Bool.self, forKey: .kept)) ?? false
        self.init(
            id: id,
            title: try c.decode(String.self, forKey: .title),
            summary: ((try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil) ?? "",
            created: ((try? c.decodeIfPresent(String.self, forKey: .created)) ?? nil) ?? "",
            expires: (try? c.decodeIfPresent(String.self, forKey: .expires)) ?? nil,
            kept: kept,
            bytes: ((try? c.decodeIfPresent(Int.self, forKey: .bytes)) ?? nil) ?? 0,
            keepDays: (try? c.decodeIfPresent(Int.self, forKey: .keepDays)) ?? nil,
            keepDaysKnown: c.contains(.keepDays)
        )
    }

    /// A copy kept for `retention` (the end date follows from when it was made).
    public func retained(_ retention: Retention, now: Date = Date()) -> Report {
        switch retention {
        case .forever:
            return Report(id: id, title: title, summary: summary, created: created, expires: nil, kept: true, bytes: bytes, keepDays: nil, keepDaysKnown: true)
        case .days(let n):
            let end = (Reports.date(created) ?? now).addingTimeInterval(Double(n) * 86_400)
            return Report(id: id, title: title, summary: summary, created: created, expires: ISO8601DateFormatter().string(from: end), kept: false, bytes: bytes, keepDays: n, keepDaysKnown: true)
        }
    }

    /// A copy with Keep switched (a kept report has no end date).
    public func keeping(_ keep: Bool, days: Int, now: Date = Date()) -> Report {
        let end = keep ? nil : (Reports.date(created) ?? now).addingTimeInterval(Double(days) * 86_400)
        return Report(id: id, title: title, summary: summary, created: created, expires: end.map { ISO8601DateFormatter().string(from: $0) }, kept: keep, bytes: bytes)
    }
}

/// The snapshot's `reports`: newest first, the room they take, and the rules.
public struct ReportShelf: Decodable, Equatable, Sendable {
    public var reports: [Report]
    public var totalBytes: Int
    public var keepDays: Int
    /// The most all reports together may take; 0 when Jarvis doesn't say.
    public var maxBytes: Int

    public init(reports: [Report], totalBytes: Int, keepDays: Int = 30, maxBytes: Int = 0) {
        self.reports = reports; self.totalBytes = totalBytes; self.keepDays = keepDays; self.maxBytes = maxBytes
    }

    enum CodingKeys: String, CodingKey { case reports, totalBytes, keepDays, maxBytes }

    /// One report that may or may not decode; a bad one is skipped.
    private struct Maybe: Decodable {
        let report: Report?
        init(from decoder: Decoder) throws { report = try? Report(from: decoder) }
    }

    /// Reads what's there; only reports the app can open (a good id) are kept.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reports = (try c.decode([Maybe].self, forKey: .reports)).compactMap(\.report).filter { Reports.isId($0.id) }
        totalBytes = ((try? c.decodeIfPresent(Int.self, forKey: .totalBytes)) ?? nil) ?? 0
        keepDays = max(1, ((try? c.decodeIfPresent(Int.self, forKey: .keepDays)) ?? nil) ?? 30)
        maxBytes = ((try? c.decodeIfPresent(Int.self, forKey: .maxBytes)) ?? nil) ?? 0
    }
}

extension Reports {
    /// Dates read the way the PC and Dylan see them.
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    /// An ISO time, with or without fractions of a second.
    public static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISODate.parse(iso)
    }

    /// A size in plain units: "850 bytes", "184 KB", "1.2 MB" (sizeText).
    public static func sizeText(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(bytes) bytes" }
        if bytes < 1_000_000 { return "\(Int((Double(bytes) / 1000).rounded())) KB" }
        let tenths = (Double(bytes) / 100_000).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths)) MB" : "\(tenths) MB"
    }

    /// When Jarvis deletes it: "Kept until you switch Keep off", "Deletes
    /// today", "Deletes tomorrow" or "Deletes Dec 18" (endText).
    public static func endText(_ report: Report, now: Date = Date()) -> String {
        guard !report.kept, let end = date(report.expires) else { return "Kept until you switch Keep off" }
        let left = end.timeIntervalSince(now)
        if left < 86_400 { return "Deletes today" }
        if left < 2 * 86_400 { return "Deletes tomorrow" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        format.dateFormat = "MMM d"
        return "Deletes \(format.string(from: end))"
    }

    /// The rule and the room used, in one line (rulesText).
    public static func rulesText(_ shelf: ReportShelf) -> String {
        let rule = "Each report is deleted \(shelf.keepDays) days after it was made, unless Keep is on."
        if shelf.reports.isEmpty { return rule }
        var room = "Using \(sizeText(shelf.totalBytes))"
        if shelf.maxBytes > 0 { room += " of \(sizeText(shelf.maxBytes))" }
        return "\(rule) \(room)."
    }
}

/// What fetching a report's page gave.
public enum ReportFetch: Equatable, Sendable {
    /// The report's HTML.
    case page(String)
    /// Deleted or expired (the server's 404).
    case gone
    /// Anything else, worded for the screen.
    case failed(String)

    /// The reader's words for a report that's gone.
    public static let goneWords = "This report was deleted or has expired."

    /// Reads the server's answer: 200 is the page, 404 is gone.
    public static func read(status: Int, data: Data) -> ReportFetch {
        switch status {
        case 200..<300: return .page(String(decoding: data, as: UTF8.self))
        case 404, 410: return .gone
        default: return .failed("Jarvis isn’t answering, so this report can’t be shown right now.")
        }
    }
}

/// How long a report is kept (Dylan, 2026-11-19: "it should just say keep 2
/// weeks which should be the default and when you tap that it can allow you
/// to change the retention").
public enum Retention: Equatable, Hashable, Sendable {
    case days(Int)
    case forever

    /// The four choices, in order.
    public static let choices: [Retention] = [.days(14), .days(30), .days(90), .forever]

    /// "Keep 2 weeks", "Keep 1 month", "Keep 3 months", "Keep forever".
    public var label: String {
        switch self {
        case .forever: return "Keep forever"
        case .days(14): return "Keep 2 weeks"
        case .days(30): return "Keep 1 month"
        case .days(90): return "Keep 3 months"
        case .days(let n): return n % 7 == 0 ? "Keep \(n / 7) weeks" : "Keep \(n) days"
        }
    }

    /// The body for POST /api/jarvis/reports: days for a span, keep true
    /// for forever.
    public func body(id: String) -> [String: Any] {
        switch self {
        case .forever: return ["op": "keep", "id": id, "keep": true]
        case .days(let n): return ["op": "keep", "id": id, "days": n]
        }
    }
}

extension Reports {
    /// The retention in force: forever when kept; the report's own days when
    /// the server says; otherwise the shelf's default (an older server).
    public static func retention(_ report: Report, defaultDays: Int) -> Retention {
        if report.kept { return .forever }
        if report.keepDaysKnown { return report.keepDays.map { .days($0) } ?? .forever }
        return .days(defaultDays)
    }

    /// The quiet line under the choices: "Deletes Dec 3", "Deletes today",
    /// or "Never deleted".
    public static func deleteLine(_ report: Report, retention: Retention, now: Date = Date()) -> String {
        if retention == .forever { return "Never deleted" }
        if report.expires == nil { return "Never deleted" }
        return endText(report, now: now)
    }

    /// The retention in words for a list row: "Kept forever", or when it goes.
    public static func retentionWords(_ report: Report, defaultDays: Int, now: Date = Date()) -> String {
        let retention = retention(report, defaultDays: defaultDays)
        return retention == .forever ? "Kept forever" : deleteLine(report, retention: retention, now: now)
    }

    /// The storage line, short enough for one line: "30-day rule · 13 KB of 200 MB".
    public static func shortRulesText(_ shelf: ReportShelf) -> String {
        var line = "Kept \(Retention.days(shelf.keepDays).label.dropFirst(5)) unless changed"
        if !shelf.reports.isEmpty {
            line += " · \(sizeText(shelf.totalBytes))"
            if shelf.maxBytes > 0 { line += " of \(sizeText(shelf.maxBytes))" }
        }
        return line
    }

    /// A row's one short line: "Nov 18 · 240 KB" (when made, and its size).
    public static func metaLine(_ report: Report) -> String {
        guard let made = date(report.created) else { return sizeText(report.bytes) }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        format.dateFormat = "MMM d"
        return "\(format.string(from: made)) · \(sizeText(report.bytes))"
    }

    /// A file name for sharing: the title made safe, with .html.
    public static func shareFileName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Report" : String(cleaned.prefix(80))) + ".html"
    }
}

/// What a retention change said back.
public enum RetentionReply: Equatable, Sendable {
    case saved
    /// The server can't take spans yet (a 400 for days on an older server).
    case notYet
    case failed(String)

    /// The words for the screen when it didn't save.
    public static let notYetWords = "Jarvis can't change that yet. Try again in a few minutes."
}
