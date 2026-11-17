// The parts of GET /api/snapshot the app's Today tab shows. Every field is
// optional on the wire side so a snapshot with a section missing (no Home
// Assistant token, an older Jarvis) still decodes.
import Foundation

/// Today's slice of the home page snapshot.
public struct Snapshot: Decodable, Sendable {
    public var generatedAt: String
    public var today: [AgendaItem]
    public var offers: Offers?
    public var home: Home?
    public var services: [Service]
    public var jobs: Jobs?

    enum CodingKeys: String, CodingKey { case generatedAt, today, offers, home, services, jobs }

    /// Decodes what's there and leaves out what isn't.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        today = try c.decodeIfPresent([AgendaItem].self, forKey: .today) ?? []
        offers = try? c.decodeIfPresent(Offers.self, forKey: .offers)
        home = try? c.decodeIfPresent(Home.self, forKey: .home)
        services = (try? c.decodeIfPresent([Service].self, forKey: .services)) ?? []
        jobs = try? c.decodeIfPresent(Jobs.self, forKey: .jobs)
    }

    /// Services that are down or struggling: the app's alert banner.
    public var alerts: [Service] {
        services.filter { $0.status == "down" || $0.status == "degraded" }
    }

    /// The first thermostat Home Assistant knows about, if any.
    public var thermostat: Device? {
        home?.devices.first { $0.kind == "climate" }
    }
}

/// One thing on today's agenda: a calendar event or a Jarvis job.
public struct AgendaItem: Decodable, Identifiable, Sendable {
    public let id: String
    public let at: String
    public let title: String
    public let detail: String?
    public let allDay: Bool?
}

/// Jarvis's greeting line and the tasks he offers to do.
public struct Offers: Decodable, Sendable {
    public let greeting: String?
    public let offers: [Offer]
}

/// One offer card: Start sends `startText` to the chat, Hide drops it.
public struct Offer: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let startText: String
}

/// Devices and weather from Home Assistant.
public struct Home: Decodable, Sendable {
    public let devices: [Device]
    public let weather: Weather?
}

/// The outside weather.
public struct Weather: Decodable, Sendable {
    public let condition: String
    public let temperature: Double?
    public let unit: String
}

/// One Home Assistant device (the app only reads thermostats for now).
public struct Device: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let state: String
    public let current: Double?
    public let target: Double?
}

/// One service on the PC and how it's doing.
public struct Service: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let status: String
}

/// Background work Dylan sent Jarvis off to do.
public struct Jobs: Decodable, Sendable {
    public let running: [RunningTask]

    enum CodingKeys: String, CodingKey { case running }

    /// An older Jarvis has no `running` list; read that as none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent([RunningTask].self, forKey: .running) ?? []
    }
}

/// One piece of background work, until it finishes.
public struct RunningTask: Decodable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let state: String
}

public enum AgendaTime {
    /// "10:00 PM" for a timed item, "All day" for an all-day one, and the raw
    /// text when it isn't a date at all (Jarvis sometimes sends "Tonight").
    public static func label(at: String, allDay: Bool, timeZone: TimeZone = .current) -> String {
        if allDay { return "All day" }
        guard let date = parse(at) else { return at }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = timeZone
        format.dateFormat = "h:mm a"
        return format.string(from: date)
    }

    /// Reads an ISO 8601 time with or without fractional seconds.
    static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
