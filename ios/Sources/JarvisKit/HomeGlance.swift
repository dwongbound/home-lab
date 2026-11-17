// What the home is doing, as a few glanceable lines with icons (Dylan,
// 2026-11-17: "it can probably add more information from Home Assistant").
// Shared by the Apple TV's Home panel, the iPad kiosk and the iPhone bedside
// display. Things needing a look come first (an open door, motion, a low
// battery), then the thermostat, what's playing, the lights, the rooms'
// temperatures and anything else that's on. An empty section shows nothing.
import Foundation

/// One line of the home glance.
public struct HomeLine: Equatable, Identifiable, Sendable {
    /// An SF Symbol.
    public let symbol: String
    public let title: String
    /// The short state on the right ("68° · heating to 70°").
    public let value: String
    /// True for things that want a look: drawn in the alert colour.
    public let attention: Bool
    public var id: String { symbol + title }
}

public enum HomeGlance {
    /// Lights are named when this many or fewer are on, else counted.
    public static let nameLightsUpTo = 3
    /// A battery at or under this percent is low.
    public static let lowBattery = 20.0

    /// The lines, most pressing first, at most `limit`.
    public static func lines(_ home: Home?, limit: Int = 7) -> [HomeLine] {
        guard let home else { return [] }
        var out = attention(home.readings ?? [])
        let devices = home.devices.filter(\.isAvailable)

        if let thermostat = devices.first(where: { $0.kind == "climate" }) {
            out.append(HomeLine(symbol: "thermometer.medium", title: thermostat.name, value: climateWords(thermostat), attention: false))
        }
        for media in devices.filter({ $0.kind == "media" && ($0.state == "playing" || $0.state == "on") }).prefix(2) {
            let symbol = media.name.lowercased().contains("tv") ? "tv.fill" : "hifispeaker.fill"
            let value = media.detail.map { $0.isEmpty ? nil : $0 } ?? nil
            out.append(HomeLine(symbol: symbol, title: media.name, value: value ?? (media.state == "playing" ? "Playing" : "On"), attention: false))
        }
        let lights = devices.filter { $0.kind == "light" }
        let lit = lights.filter(\.isOn)
        if !lit.isEmpty {
            let value = lit.count <= nameLightsUpTo
                ? lit.map(\.name).joined(separator: ", ")
                : "\(lit.count) of \(lights.count) on"
            out.append(HomeLine(symbol: "lightbulb.fill", title: lit.count == 1 ? "Light on" : "Lights on", value: value, attention: false))
        }
        out += rooms(home.readings ?? [])
        for device in devices.filter({ ["fan", "lock", "cover"].contains($0.kind) && isNoteworthy($0) }).prefix(2) {
            out.append(HomeLine(symbol: TodayWording.deviceSymbol(device), title: device.name, value: TodayWording.deviceState(device), attention: device.kind == "lock"))
        }
        return Array(out.prefix(limit))
    }

    /// Open doors and windows, motion and low batteries.
    static func attention(_ readings: [Reading]) -> [HomeLine] {
        readings.compactMap { reading in
            let value = reading.value.lowercased()
            switch reading.kind {
            case "door" where value == "open":
                return HomeLine(symbol: "door.left.hand.open", title: reading.name, value: "Open", attention: true)
            case "window" where value == "open":
                return HomeLine(symbol: "window.vertical.open", title: reading.name, value: "Open", attention: true)
            case "motion" where value == "detected" || value == "on":
                return HomeLine(symbol: "figure.walk.motion", title: reading.name, value: "Motion", attention: true)
            case "battery":
                if value == "low" {
                    return HomeLine(symbol: "battery.25percent", title: reading.name, value: "Battery low", attention: true)
                }
                if let percent = Double(value), percent <= lowBattery {
                    return HomeLine(symbol: "battery.25percent", title: reading.name, value: "Battery \(Int(percent))%", attention: true)
                }
                return nil
            default:
                return nil
            }
        }
    }

    /// Each room's temperature and humidity on one line ("Bedroom 70° · 45%").
    static func rooms(_ readings: [Reading]) -> [HomeLine] {
        var order: [String] = []
        var parts: [String: (temperature: String?, humidity: String?)] = [:]
        for reading in readings where reading.kind == "temperature" || reading.kind == "humidity" {
            guard let number = Double(reading.value) else { continue }
            if parts[reading.name] == nil { order.append(reading.name); parts[reading.name] = (nil, nil) }
            if reading.kind == "temperature" {
                parts[reading.name]?.temperature = "\(Int(number.rounded()))°"
            } else {
                parts[reading.name]?.humidity = "\(Int(number.rounded()))% humidity"
            }
        }
        return order.prefix(3).map { name in
            let p = parts[name]!
            let value = [p.temperature, p.humidity].compactMap { $0 }.joined(separator: " · ")
            return HomeLine(symbol: p.temperature != nil ? "thermometer.variable" : "humidity.fill", title: name, value: value, attention: false)
        }
    }

    /// "68° · heating to 70°", "70° · off".
    static func climateWords(_ device: Device) -> String {
        var parts: [String] = []
        if let current = device.current { parts.append("\(Int(current.rounded()))°") }
        let doing = (device.detail?.isEmpty == false ? device.detail! : device.state).replacingOccurrences(of: "_", with: " ")
        if let target = device.target, device.state != "off" {
            parts.append("\(doing) to \(Int(target.rounded()))°")
        } else {
            parts.append(doing)
        }
        return parts.joined(separator: " · ")
    }

    /// A fan running, a lock unlocked, blinds open.
    static func isNoteworthy(_ device: Device) -> Bool {
        switch device.kind {
        case "lock": return device.state == "unlocked" || device.state == "open"
        case "cover": return device.state == "open"
        default: return device.isOn
        }
    }

    /// "40% humidity · wind 6 mph", or nil when there's neither.
    public static func weatherExtra(_ weather: Weather?) -> String? {
        guard let weather else { return nil }
        var parts: [String] = []
        if let humidity = weather.humidity { parts.append("\(Int(humidity.rounded()))% humidity") }
        if let wind = weather.wind { parts.append("wind \(Int(wind.rounded())) \(weather.windUnit ?? "mph")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
