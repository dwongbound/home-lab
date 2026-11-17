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
}
