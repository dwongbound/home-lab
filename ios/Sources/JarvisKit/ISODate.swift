// One reader for the ISO 8601 times Jarvis sends, made once and remembered
// (2026-11-20 device trace: about 70% of the main thread while switching
// tabs went to building a new date formatter for every notice comparison,
// on every redraw). ISO8601DateFormatter is safe to share across threads.
import Foundation

public enum ISODate {
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let cache: NSCache<NSString, NSDate> = {
        let c = NSCache<NSString, NSDate>()
        c.countLimit = 2000
        return c
    }()

    /// The time in `text`, with or without fractions of a second.
    public static func parse(_ text: String) -> Date? {
        if let hit = cache.object(forKey: text as NSString) { return hit as Date }
        guard let date = plain.date(from: text) ?? fractional.date(from: text) else { return nil }
        cache.setObject(date as NSDate, forKey: text as NSString)
        return date
    }

    /// A time as ISO text (no fractions).
    public static func string(_ date: Date) -> String { plain.string(from: date) }
}
