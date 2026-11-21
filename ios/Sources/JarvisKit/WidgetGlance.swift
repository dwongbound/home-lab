// What the Home Screen and Lock Screen widgets show (Dylan, 2026-11-21:
// "can we build widgets for ipad and iphone"). The app writes this small
// summary into the app group each time it reads a snapshot; the widgets
// read it back, so they cost no network and show the same as the app.
// Nothing about money, ever; health is only last night's sleep.
import Foundation

public struct WidgetGlance: Codable, Equatable, Sendable {
    /// When the app last heard from Jarvis.
    public var updated: Date
    /// Unread notices, and whether one needs him (an approval).
    public var unread: Int
    public var needsYou: Bool
    /// How many need him (approvals).
    public var needCount: Int = 0
    /// Jobs Jarvis is running.
    public var running: Int
    /// Today's agenda and events still to come (and ones in progress).
    public var agenda: [Item]
    public var sleep: Sleep?
    /// The newest unread notice's title, as Jarvis wrote it.
    public var newestNotice: String?
    /// The newest few unread notice titles, newest first (medium widgets).
    public var notices: [String]?
    /// "Cloudy, 61°F".
    public var weather: String?
    /// Today's food: calories left of the goal, protein (the Watch's numbers).
    public var food: Food?
    /// Home at a glance: the thermostat and what's on.
    public var home: HomeLine?
    /// The week's sleep scores, oldest first (nil for a night without one).
    public var sleepWeek: [Int?] = []

    public struct Food: Codable, Equatable, Sendable {
        public var left: Double
        public var goal: Double
        public var protein: Double?
        public var proteinGoal: Double?
        public init(left: Double, goal: Double, protein: Double?, proteinGoal: Double?) {
            self.left = left; self.goal = goal; self.protein = protein; self.proteinGoal = proteinGoal
        }
    }

    public struct HomeLine: Codable, Equatable, Sendable {
        /// "68°", the room now, and where it's heading ("to 70°").
        public var temperature: String?
        public var thermostat: String?
        public var lightsOn: Int
        public var lights: Int
        /// Names of what's on or playing, a few.
        public var on: [String]
    }

    public struct Item: Codable, Equatable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date?
        public var allDay: Bool
        public init(title: String, start: Date, end: Date?, allDay: Bool) {
            self.title = title; self.start = start; self.end = end; self.allDay = allDay
        }
    }

    public struct Sleep: Codable, Equatable, Sendable {
        public var score: Int?
        public var band: String?
        public var bandWord: String?
        /// "7h 20m".
        public var asleep: String?
        /// "Last night", or "Thursday night".
        public var when: String?
        /// The stage bar: stage key and share of the night.
        public var stages: [Share]
        public struct Share: Codable, Equatable, Sendable {
            public var stage: String
            public var fraction: Double
        }
    }

    public init(updated: Date, unread: Int, needsYou: Bool, running: Int, agenda: [Item], sleep: Sleep?) {
        self.updated = updated; self.unread = unread; self.needsYou = needsYou
        self.running = running; self.agenda = agenda; self.sleep = sleep
    }

    /// The app group both the app and the widgets can read.
    public static let appGroup = "group.com.dwongbound.jarvis"
    public static let key = "widget.glance"

    /// From a snapshot: notices, running jobs, today's remaining agenda and
    /// last night's sleep.
    public static func from(_ snapshot: Snapshot, now: Date = Date(), calendar: Calendar = .current) -> WidgetGlance {
        let unread = snapshot.notices.filter { !$0.kept }
        var items: [Item] = []
        for item in snapshot.today {
            guard let start = AgendaTime.parse(item.at) else { continue }
            items.append(Item(title: item.title, start: start, end: nil, allDay: item.allDay ?? false))
        }
        for event in snapshot.events where !items.contains(where: { $0.title == event.title }) {
            guard let start = AgendaTime.parse(event.start), calendar.isDate(start, inSameDayAs: now) || event.allDay == true else { continue }
            items.append(Item(title: event.title, start: start, end: event.end.flatMap(AgendaTime.parse), allDay: event.allDay ?? false))
        }
        let ahead = items
            .filter { ($0.end ?? $0.start.addingTimeInterval(NowNext.assumedLength)) > now }
            .sorted { $0.start < $1.start }
        var sleep: Sleep?
        if snapshot.sleep != nil {
            let card = SleepSlide.card(snapshot, now: now)
            if card.kind == .night {
                sleep = Sleep(score: card.score, band: card.band, bandWord: card.bandWord, asleep: card.asleep, when: card.whenWords,
                              stages: card.stages.map { Sleep.Share(stage: $0.stage, fraction: $0.fraction) })
            }
        }
        var glance = WidgetGlance(updated: now, unread: unread.count, needsYou: unread.contains { $0.kind == .need },
                                  running: snapshot.jobs?.running.count ?? 0, agenda: Array(ahead.prefix(6)), sleep: sleep)
        glance.newestNotice = Notices.sorted(unread).first?.title
        glance.notices = Notices.sorted(unread).prefix(3).map(\.title)
        glance.needCount = unread.filter { $0.kind == .need }.count
        if let weather = snapshot.home?.weather {
            glance.weather = TodayWording.weatherWords(weather.condition) + (weather.temperature.map { ", \(Int($0.rounded()))\(weather.unit)" } ?? "")
        }
        if let n = snapshot.nutrition {
            glance.food = Food(left: n.left, goal: n.goal, protein: n.protein, proteinGoal: n.proteinGoal)
        }
        if let home = snapshot.home {
            let devices = home.devices.filter(\.isAvailable)
            let lights = devices.filter { $0.kind == "light" }
            let thermostat = devices.first { $0.kind == "climate" }
            glance.home = HomeLine(
                temperature: thermostat?.current.map { "\(Int($0.rounded()))°" },
                thermostat: thermostat.flatMap { t in t.state == "off" ? "Off" : t.target.map { "\(t.detail?.capitalized ?? "Set") to \(Int($0.rounded()))°" } },
                lightsOn: lights.filter(\.isOn).count, lights: lights.count,
                on: devices.filter { $0.isOn && $0.kind != "climate" }.map(\.name).prefix(4).map { $0 })
        }
        if let trend = snapshot.sleep?.trend {
            glance.sleepWeek = trend.prefix(7).reversed().map(\.score)
        }
        return glance
    }

    /// The items still to come at `date` (the widget's own clock), at most `limit`.
    public func upcoming(at date: Date, limit: Int) -> [Item] {
        Array(agenda.filter { ($0.end ?? $0.start.addingTimeInterval(NowNext.assumedLength)) > date }.prefix(limit))
    }

    /// "4 new", "1 needs you", or nil when there's nothing.
    public var noticeWords: String? {
        if needsYou {
            let need = max(1, needCount)
            return unread == need ? "\(need) need\(need == 1 ? "s" : "") you" : "\(unread) new · \(need) need\(need == 1 ? "s" : "") you"
        }
        return unread > 0 ? "\(unread) new" : nil
    }

    /// The Lock Screen's two short lines: "4 new" then "1 needs you" or
    /// "2 running" (each short enough never to be cut).
    public var lockLines: [String] {
        var lines = [unread > 0 ? "\(unread) new" : "Nothing new"]
        if needsYou {
            let need = max(1, needCount)
            lines.append("\(need) need\(need == 1 ? "s" : "") you")
        } else if running > 0 {
            lines.append("\(running) running")
        }
        return lines
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> WidgetGlance? {
        data.flatMap { try? JSONDecoder().decode(WidgetGlance.self, from: $0) }
    }
}
