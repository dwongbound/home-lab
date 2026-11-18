// Sample data for checking layouts in the simulator without the PC.
import Foundation

#if DEBUG
/// A sample snapshot for checking layouts in the simulator without the PC:
/// debug builds launched with `-demoSnapshot` only.
public enum DemoSnapshot {
    /// The demo's "now": the `-lampAt HH:MM` time today if given (so the
    /// TV's pinned clock and the sample events agree), else the real time.
    public static var now: Date {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lampAt"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) {
                return date
            }
        }
        return Date()
    }

    public static var snapshot: Snapshot? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demoSnapshot") else { return nil }
        return build(now: Self.now, sparse: args.contains("-demoSparse"))
    }

    /// The sample snapshot at `now` (full, or `sparse` for the near-empty
    /// case). Split out so a test can check it still decodes.
    static func build(now: Date, sparse: Bool) -> Snapshot? {
        let iso = { (offset: Double) in ISO8601DateFormatter().string(from: now.addingTimeInterval(offset * 60)) }
        let cal = Calendar.current
        let sunrise = ISO8601DateFormatter().string(from: cal.date(bySettingHour: 6, minute: 28, second: 0, of: now) ?? now)
        let sunset = ISO8601DateFormatter().string(from: cal.date(bySettingHour: 16, minute: 48, second: 0, of: now) ?? now)
        let tomorrow9 = ISO8601DateFormatter().string(from: cal.date(byAdding: .day, value: 1, to: cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now) ?? now)
        if sparse {
            let json = """
            {"generatedAt":"x","services":[{"id":"j","name":"Jarvis","detail":"","status":"up"}],"today":[],
             "home":{"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"off","current":69}],
               "weather":{"condition":"sunny","temperature":66,"unit":"°F"},"sun":{"rising":"\(sunrise)","setting":"\(sunset)"}}}
            """
            return try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        }
        let forecast = (1...10).map { h in
            let conditions = ["cloudy", "cloudy", "partlycloudy", "rainy", "rainy", "cloudy", "partlycloudy", "clear-night", "clear-night", "sunny"]
            return #"{"at":"\#(iso(Double(h) * 60))","condition":"\#(conditions[h - 1])","temperature":\#(62 - h),"rain":\#([10, 20, 40, 70, 60, 30, 10, 0, 0, 0][h - 1])}"#
        }.joined(separator: ",")
        let json = """
        {"generatedAt":"x",
         "notices":[{"id":"n1","kind":"need","title":"Turn off the bedroom lights?","body":"Jarvis wants to run home_service light.turn_off","source":"approval","created":"\(iso(-3))","approvalId":"ap1"},
                    {"id":"n2","kind":"heads","title":"PS5 Pro back in stock at Target","body":"Lookout spotted it 10 minutes ago","source":"lookout","created":"\(iso(-12))"},
                    {"id":"n3","kind":"fyi","title":"Reminder code rewrite finished","body":"Changing my code so reminders repeat: done","source":"job","created":"\(iso(-95))"}],
         "services":[{"id":"h","name":"Home Assistant","detail":"","status":"up"},{"id":"o","name":"Ollama","detail":"","status":"idle"},{"id":"j","name":"Jarvis","detail":"","status":"up"}],
         "today":[{"id":"jarvis-a@0830","at":"\(iso(-300))","title":"Marketplace deal watch","detail":"Jarvis: scan","status":"done"},
                  {"id":"c1","at":"\(iso(-150))","title":"Lunch with Sam"},
                  {"id":"c2","at":"\(iso(42))","title":"Volleyball at the Y"},
                  {"id":"jarvis-b@1900","at":"\(iso(120))","title":"Follow up on dinner plans","detail":"Jarvis: reminder"},
                  {"id":"c3","at":"\(iso(180))","title":"CG x SOW rehearsal"}],
         "offers":{"greeting":"Good evening, Dylan. Volleyball is up next and I'm rewriting the reminder code in the background.","offers":[{"id":"o1","title":"Draft the rehearsal set list","body":"","startText":""}]},
         "home":{"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"heat","detail":"heating","current":68,"target":70,"humidity":44},
            {"id":"a","name":"Entrance","kind":"light","state":"on"},{"id":"b","name":"Hall","kind":"light","state":"off"},
            {"id":"e","name":"Desk","kind":"light","state":"on","brightness":0.6},
            {"id":"g","name":"Bed lamp","kind":"light","state":"on"},
            {"id":"c","name":"Dylans Apple TV","kind":"media","state":"playing","detail":"Severance · Apple TV+"},
            {"id":"f","name":"Bedroom","kind":"media","state":"paused","detail":"Lo-fi beats"},
            {"id":"d","name":"Dylan asleep","kind":"switch","state":"off"}],
          "powerWatts":43,
          "forecast":[\(forecast)],
          "weather":{"condition":"cloudy","temperature":61,"unit":"°F","humidity":72,"wind":6,"windUnit":"mph"},"sun":{"rising":"\(sunrise)","setting":"\(sunset)"}},
         "jobs":{"running":[{"id":"j1","label":"Changing my code so reminders repeat","state":"running","startedAt":"\(iso(-9))"}],
                 "lookout":{"checks":["calendar","email"],"watching":["Flight prices to Tokyo in March","The PS5 Pro restock at Target"],"heldBack":[{"text":"x","reason":null},{"text":"y","reason":null}]},
                 "messenger":{"sentToday":3,"cap":8,"quiet":"10 PM–7 AM"}},
         "cloud":{"health":{"yesterday":{"steps":9580},"sleep":{"asleep_min":422}},
                  "calendar":[{"id":"c1","title":"Lunch with Sam","start":"\(iso(-150))","end":"\(iso(-90))","allDay":false,"location":"Tender Greens"},
                              {"id":"c2","title":"Volleyball at the Y","start":"\(iso(42))","end":"\(iso(132))","allDay":false,"location":"Westside YMCA"},
                              {"id":"c3","title":"CG x SOW rehearsal","start":"\(iso(180))","end":"\(iso(300))","allDay":false},
                              {"id":"c4","title":"Dentist","start":"\(tomorrow9)","allDay":false}],
                  "money":{"netWorth":1}}}
        """
        return try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }
}
#endif
