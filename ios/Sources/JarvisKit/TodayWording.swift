// Small wordings shared by Today, the kiosks and the Apple TV: the
// greeting, money, hours, sun times, weather symbols and device states.
import Foundation

/// The small wordings Today needs: greeting, money, hours, device states.
public enum TodayWording {
    /// "Good morning" until noon, "Good afternoon" until 5, then "Good evening".
    public static func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 5 { return "Good evening" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    /// "$127,313" (no cents: Today is a glance).
    public static func dollars(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// 422 minutes as "7h 2m".
    public static func hours(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    /// An ISO time as "4:48 PM" in the phone's zone.
    public static func time(_ iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// An SF Symbol for Home Assistant's weather words.
    public static func weatherSymbol(_ condition: String) -> String {
        switch condition.lowercased() {
        case let c where c.contains("sun") || c.contains("clear"): return "sun.max.fill"
        case let c where c.contains("partly"): return "cloud.sun.fill"
        case let c where c.contains("rain") || c.contains("pour"): return "cloud.rain.fill"
        case let c where c.contains("snow"): return "cloud.snow.fill"
        case let c where c.contains("fog"): return "cloud.fog.fill"
        case let c where c.contains("lightning") || c.contains("storm"): return "cloud.bolt.rain.fill"
        case let c where c.contains("wind"): return "wind"
        default: return "cloud.fill"
        }
    }

    /// An SF Symbol per kind of device.
    public static func deviceSymbol(_ device: Device) -> String {
        switch device.kind {
        case "light": return device.isOn ? "lightbulb.fill" : "lightbulb"
        case "climate": return "thermometer.medium"
        case "media": return device.name.lowercased().contains("tv") ? "tv.fill" : "hifispeaker.fill"
        case "lock": return device.isOn ? "lock.open.fill" : "lock.fill"
        case "fan": return "fan.fill"
        case "cover": return "blinds.vertical.closed"
        default: return device.name.lowercased().contains("asleep") ? "moon.fill" : "switch.2"
        }
    }

    /// "On", "Off", "68° · heat to 70°", "Playing".
    public static func deviceState(_ device: Device) -> String {
        if device.kind == "climate" {
            var parts: [String] = []
            if let current = device.current { parts.append("\(Int(current.rounded()))°") }
            if let target = device.target, device.state != "off" {
                parts.append("\(device.state) to \(Int(target.rounded()))°")
            } else {
                parts.append(device.state.capitalized)
            }
            return parts.joined(separator: " · ")
        }
        return device.state.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// "Sunset 4:48 PM · Sunrise 6:28 AM": the next of the two first. The
    /// snapshot has today's times; one already past rolls on to tomorrow.
    public static func sunLine(rising: String?, setting: String?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        let format = ISO8601DateFormatter()
        var events: [(String, Date)] = []
        if let rising, let date = format.date(from: rising) { events.append(("Sunrise", date)) }
        if let setting, let date = format.date(from: setting) { events.append(("Sunset", date)) }
        guard !events.isEmpty else { return nil }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US")
        clock.timeZone = timeZone
        clock.dateFormat = "h:mm a"
        return events
            .map { name, date in (name, date < now ? date.addingTimeInterval(86_400) : date) }
            .sorted { $0.1 < $1.1 }
            .map { "\($0.0) \(clock.string(from: $0.1))" }
            .joined(separator: " · ")
    }

    /// Jarvis's greeting as a headline and the rest (Dylan, 2026-11-17:
    /// "put emphasis on the beginning thing like late night, Dylan"). Splits
    /// at the first sentence break or dash; failing that, at the comma after
    /// the name ("Late night, Dylan, you've …"). No rest → body is nil.
    public static func greetingParts(_ text: String) -> (headline: String, body: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let breaks = [". ", "! ", "? ", " — ", " – ", " - ", ": "]
        let first = breaks.compactMap { mark in trimmed.range(of: mark).map { (mark, $0) } }
            .min { $0.1.lowerBound < $1.1.lowerBound }
        if let (mark, range) = first, trimmed.distance(from: trimmed.startIndex, to: range.lowerBound) <= 60 {
            var head = String(trimmed[..<range.lowerBound])
            if mark.hasPrefix("!") || mark.hasPrefix("?") { head += String(mark.first!) }
            let body = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return (head, body.isEmpty ? nil : body)
        }
        let commas = trimmed.indices.filter { trimmed[$0] == "," }
        if commas.count >= 2, trimmed.distance(from: trimmed.startIndex, to: commas[1]) <= 40 {
            let body = trimmed[trimmed.index(after: commas[1])...].trimmingCharacters(in: .whitespaces)
            if !body.isEmpty {
                return (String(trimmed[..<commas[1]]), body.prefix(1).uppercased() + body.dropFirst())
            }
        }
        var head = trimmed
        if head.hasSuffix(".") { head.removeLast() }
        return (head, nil)
    }

    /// Home Assistant's weather word as words: "partlycloudy" → "Partly cloudy",
    /// "clear-night" → "Clear", "lightning-rainy" → "Lightning, rainy".
    public static func weatherWords(_ condition: String) -> String {
        let known = [
            "partlycloudy": "Partly cloudy", "clear-night": "Clear", "lightning-rainy": "Thunderstorms",
            "snowy-rainy": "Sleet", "windy-variant": "Windy", "exceptional": "Unusual weather",
        ]
        if let words = known[condition.lowercased()] { return words }
        let spaced = condition.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
