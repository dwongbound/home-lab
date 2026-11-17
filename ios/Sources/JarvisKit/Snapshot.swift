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
    /// Money from the cloud digest (Copilot), nil until the digest has read it.
    public var money: Money?
    /// Sleep and steps from the cloud digest (Apple Health by way of the PC).
    public var health: Health?
    /// Calendar events from the cloud digest, with their end and place.
    public var events: [CalendarEvent] = []

    enum CodingKeys: String, CodingKey { case generatedAt, today, offers, home, services, jobs, cloud }

    /// The cloud digest; the app only reads its money section.
    private struct Cloud: Decodable {
        let money: Money?
        let health: Health?
        let calendar: [CalendarEvent]?

        enum CodingKeys: String, CodingKey { case money, health, calendar }

        /// Any section that won't decode is left out.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            money = try? c.decodeIfPresent(Money.self, forKey: .money)
            health = try? c.decodeIfPresent(Health.self, forKey: .health)
            calendar = try? c.decodeIfPresent([CalendarEvent].self, forKey: .calendar)
        }
    }

    /// Decodes what's there and leaves out what isn't.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        today = try c.decodeIfPresent([AgendaItem].self, forKey: .today) ?? []
        offers = try? c.decodeIfPresent(Offers.self, forKey: .offers)
        home = try? c.decodeIfPresent(Home.self, forKey: .home)
        services = (try? c.decodeIfPresent([Service].self, forKey: .services)) ?? []
        jobs = try? c.decodeIfPresent(Jobs.self, forKey: .jobs)
        let cloud = try? c.decodeIfPresent(Cloud.self, forKey: .cloud)
        money = cloud?.money
        events = cloud?.calendar ?? []
        health = cloud?.health
    }

    /// Services that are down or struggling: the app's alert banner.
    public var alerts: [Service] {
        services.filter { $0.status == "down" || $0.status == "degraded" }
    }

    /// The first thermostat Home Assistant knows about, if any.
    /// Devices worth a tile on Today: answering, and not scenes or scripts.
    public var homeTiles: [Device] {
        (home?.devices ?? []).filter { device in
            device.isAvailable && ["climate", "light", "media", "switch", "fan", "lock", "cover"].contains(device.kind)
        }
    }

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
    public let sun: Sun?
    /// Sensor readings, the ones needing a look first. Missing on an older
    /// server.
    public let readings: [Reading]?
    /// Hourly forecast, up to 12 hours. Missing on an older server.
    public let forecast: [ForecastHour]?
    /// What the lights draw right now, in watts.
    public let powerWatts: Int?

    enum CodingKeys: String, CodingKey { case devices, weather, sun, readings, forecast, powerWatts }

    /// A section that won't decode reads as missing, not as a failure.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = (try? c.decodeIfPresent([Device].self, forKey: .devices)) ?? []
        weather = try? c.decodeIfPresent(Weather.self, forKey: .weather)
        sun = try? c.decodeIfPresent(Sun.self, forKey: .sun)
        readings = try? c.decodeIfPresent([Reading].self, forKey: .readings)
        forecast = try? c.decodeIfPresent([ForecastHour].self, forKey: .forecast)
        powerWatts = (try? c.decodeIfPresent(Int.self, forKey: .powerWatts)) ?? (try? c.decodeIfPresent(Double.self, forKey: .powerWatts)).flatMap { $0.map { Int($0.rounded()) } }
    }
}

/// One hour of the forecast.
public struct ForecastHour: Decodable, Sendable, Equatable {
    public let at: String
    public let condition: String
    public let temperature: Double?
    public let low: Double?
    /// Chance of rain, percent.
    public let rain: Double?
}

/// One calendar event (the cloud digest's calendar).
public struct CalendarEvent: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let start: String
    public let end: String?
    public let allDay: Bool?
    public let location: String?

    public init(id: String, title: String, start: String, end: String?, allDay: Bool? = false, location: String? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay; self.location = location
    }
}

/// One Home Assistant sensor: a room's temperature or humidity, a door or
/// window, motion, or a battery.
public struct Reading: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// temperature, humidity, door, window, motion or battery.
    public let kind: String
    /// A number as text ("70.5"), or "open", "detected", "low".
    public let value: String
    public let unit: String?
}

/// Today's sunrise and sunset (ISO times).
public struct Sun: Decodable, Sendable {
    public let rising: String?
    public let setting: String?
}

/// The outside weather.
public struct Weather: Decodable, Sendable {
    public let condition: String
    public let temperature: Double?
    public let unit: String
    /// Percent.
    public let humidity: Double?
    /// In Home Assistant's own unit (`windUnit`).
    public let wind: Double?
    public let windUnit: String?
}

/// One Home Assistant device: a light, switch, fan, speaker, scene or thermostat.
public struct Device: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let state: String
    /// False when Home Assistant can't reach it.
    public let available: Bool?
    /// Lights only, 0..1.
    public let brightness: Double?
    /// What's playing, or what a thermostat is doing ("heating").
    public let detail: String?
    public let current: Double?
    public let target: Double?
    /// Indoor humidity, percent (thermostats that report it).
    public let humidity: Double?

    /// True when it's on, playing, or (a thermostat) running a mode.
    /// Home Assistant can reach it.
    public var isAvailable: Bool {
        (available ?? true) && state != "unavailable" && state != "unknown"
    }

    public var isOn: Bool {
        if kind == "climate" { return state != "off" }
        return state == "on" || state == "playing"
    }
}

/// Money from Copilot, by way of the cloud digest. Amounts are US dollars;
/// a credit or loan balance is what's owed.
public struct Money: Decodable, Sendable {
    public let netWorth: Double?
    public let accounts: [Account]
    public let spending: Spending?
    /// Spending by category this month, with any budget set for it.
    public let categories: [Category]
    /// Anything worth a look: a big charge, a new subscription, a low balance.
    public let flags: [Flag]
    /// Newest first; a negative amount is money coming in.
    public let recent: [Transaction]

    enum CodingKeys: String, CodingKey { case netWorth, accounts, spending, categories, flags, recent }

    /// Any missing list reads as empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        netWorth = try? c.decodeIfPresent(Double.self, forKey: .netWorth)
        accounts = (try? c.decodeIfPresent([Account].self, forKey: .accounts)) ?? []
        spending = try? c.decodeIfPresent(Spending.self, forKey: .spending)
        categories = (try? c.decodeIfPresent([Category].self, forKey: .categories)) ?? []
        flags = (try? c.decodeIfPresent([Flag].self, forKey: .flags)) ?? []
        recent = (try? c.decodeIfPresent([Transaction].self, forKey: .recent)) ?? []
    }

    /// Cash on hand: every cash account added up.
    public var cash: Double {
        accounts.filter { $0.kind == "cash" }.reduce(0) { $0 + $1.balance }
    }

    /// Owed on cards right now.
    public var cardDebt: Double {
        accounts.filter { $0.kind == "credit" }.reduce(0) { $0 + $1.balance }
    }

    /// Budgeted categories already past their budget, worst first.
    public var overBudget: [Category] {
        categories
            .filter { ($0.budget ?? 0) > 0 && $0.spent > ($0.budget ?? 0) }
            .sorted { $0.spent / ($0.budget ?? 1) > $1.spent / ($1.budget ?? 1) }
    }

    public struct Category: Decodable, Sendable {
        public let name: String
        public let spent: Double
        public let budget: Double?
    }

    public struct Account: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let kind: String
        public let balance: Double
    }

    public struct Spending: Decodable, Sendable {
        public let thisMonth: Double
        public let lastMonthToDate: Double?
        public let budget: Double?
    }

    public struct Flag: Decodable, Identifiable, Sendable {
        public let id: String
        public let text: String
    }

    public struct Transaction: Decodable, Identifiable, Sendable {
        public let id: String
        public let date: String
        public let merchant: String
        public let amount: Double
    }
}

/// "$1,234" (no cents), for money on a small screen.
public enum MoneyText {
    public static func dollars(_ amount: Double) -> String {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.currencyCode = "USD"
        format.locale = Locale(identifier: "en_US")
        format.maximumFractionDigits = 0
        return format.string(from: NSNumber(value: amount.rounded())) ?? "$\(Int(amount))"
    }
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
    /// What Lookout is keeping an eye on.
    public let lookout: Lookout?
    /// How many messages Jarvis has sent today.
    public let messenger: Messenger?

    enum CodingKeys: String, CodingKey { case running, lookout, messenger }

    /// An older Jarvis has no `running` list; read that as none. Lookout and
    /// Messenger are optional and skipped if they won't decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent([RunningTask].self, forKey: .running) ?? []
        lookout = try? c.decodeIfPresent(Lookout.self, forKey: .lookout)
        messenger = try? c.decodeIfPresent(Messenger.self, forKey: .messenger)
    }
}

/// Lookout: what it checked last, what it's watching, what it held back.
public struct Lookout: Decodable, Sendable {
    public let checks: [String]
    public let watching: [String]
    /// How many things it decided not to bother Dylan with (the texts are
    /// private and never shown on the TV).
    public let heldBackCount: Int

    enum CodingKeys: String, CodingKey { case checks, watching, heldBack }
    private struct Held: Decodable {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checks = (try? c.decodeIfPresent([String].self, forKey: .checks)) ?? []
        watching = (try? c.decodeIfPresent([String].self, forKey: .watching)) ?? []
        heldBackCount = ((try? c.decodeIfPresent([Held].self, forKey: .heldBack)) ?? []).count
    }
}

/// Messenger: messages sent today against the daily cap, and quiet hours.
public struct Messenger: Decodable, Sendable {
    public let sentToday: Int
    public let cap: Int?
    public let quiet: String?
}

/// One piece of background work, until it finishes.
public struct RunningTask: Decodable, Identifiable, Sendable {
    public let id: String
    public let label: String
    /// "running" or "queued".
    public let state: String
    /// When it started (ISO), if Jarvis said.
    public let startedAt: String?

    public init(id: String, label: String, state: String, startedAt: String? = nil) {
        self.id = id
        self.label = label
        self.state = state
        self.startedAt = startedAt
    }

    /// "Queued", "Just started", "Running for 4 min", "Running for 1 h 5 min".
    public func runningWords(now: Date = Date()) -> String {
        if state == "queued" { return "Queued" }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let startedAt, let start = fractional.date(from: startedAt) ?? plain.date(from: startedAt) else { return "Running" }
        let minutes = Int(now.timeIntervalSince(start) / 60)
        if minutes < 1 { return "Just started" }
        if minutes < 60 { return "Running for \(minutes) min" }
        return "Running for \(minutes / 60) h \(minutes % 60) min"
    }
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

/// Sleep and activity from the digest (Apple Health by way of the PC).
public struct Health: Decodable, Sendable {
    public let yesterday: Day?
    public let sleep: Sleep?

    public struct Day: Decodable, Sendable {
        public let steps: Int?
        public let activeKcal: Int?
    }

    public struct Sleep: Decodable, Sendable {
        public let asleepMin: Int?
        public let deepMin: Int?
        public let remMin: Int?

        enum CodingKeys: String, CodingKey {
            case asleepMin = "asleep_min", deepMin = "deep_min", remMin = "rem_min"
        }
    }
}
