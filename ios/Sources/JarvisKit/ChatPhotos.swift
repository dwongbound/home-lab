// Photos in the chat (Dylan, 2026-11-18: "add images… I want to be able to
// send my food pictures to Jarvis. Then I can completely remove Telegram").
// The plain rules: how many, how big, how they're squeezed before sending,
// and how they ride in the chat request. The app does the pixels.
import Foundation

/// One photo ready to send: JPEG bytes as base64 (no data: prefix).
public struct ChatPhoto: Equatable, Sendable {
    public let mediaType: String
    public let base64: String

    public init(jpeg: Data) {
        mediaType = "image/jpeg"
        base64 = jpeg.base64EncodedString()
    }

    /// As the chat request carries it.
    public var json: [String: String] { ["media_type": mediaType, "data": base64] }
}

public enum PhotoLimits {
    /// At most this many photos in one message.
    public static let maxPhotos = 4
    /// The long side, in pixels, after shrinking.
    public static let maxSide: Double = 1600
    /// JPEG quality to start at, and the size to get under.
    public static let startQuality: Double = 0.8
    public static let maxBytes = 3_000_000

    /// A photo's size shrunk so its long side is at most `maxSide`
    /// (never enlarged), rounded to whole pixels.
    public static func scaled(width: Double, height: Double) -> (width: Double, height: Double) {
        let long = max(width, height)
        guard long > maxSide, long > 0 else { return (width.rounded(), height.rounded()) }
        let k = maxSide / long
        return ((width * k).rounded(), (height * k).rounded())
    }

    /// The next JPEG quality to try when a photo is still too big, or nil
    /// when it's as low as it sensibly goes.
    public static func lowerQuality(after quality: Double) -> Double? {
        let next = ((quality - 0.15) * 100).rounded() / 100
        return next >= 0.3 ? next : nil
    }

    /// How many more photos can be added to a message already holding `n`.
    public static func room(holding n: Int) -> Int { max(0, maxPhotos - n) }

    /// What to say when the server refuses (400): a photo it couldn't take.
    public static let refusedWords = "That photo couldn't be sent"

    /// "1 photo", "3 photos": the chip on a past message whose photos
    /// aren't on this device.
    public static func chip(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }
}

/// The answers to "is this the meal I already logged?".
public enum MealChoice {
    public static let all = ["same", "leftovers", "new"]

    /// The button's words.
    public static func label(_ choice: String) -> String {
        switch choice {
        case "same": return "Same meal"
        case "leftovers": return "Leftovers"
        default: return "New meal"
        }
    }
}

/// Where a sent message's photo thumbnails are kept on this device, since
/// history never sends the photos back: a stable name from the words and
/// how many photos, so the bubble finds them after a relaunch.
public enum PhotoCacheKey {
    public static func key(text: String, count: Int) -> String {
        var h: UInt64 = 1469598103934665603
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return String(format: "%016llx-%d", h, count)
    }
}

