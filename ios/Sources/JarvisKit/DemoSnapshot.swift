// Sample data for checking layouts in the simulator without the PC.
import Foundation

#if DEBUG
/// A sample snapshot for checking layouts in the simulator without the PC:
/// debug builds launched with `-demoSnapshot` only.
public enum DemoSnapshot {
    public static var snapshot: Snapshot? {
        guard ProcessInfo.processInfo.arguments.contains("-demoSnapshot") else { return nil }
        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(25 * 60))
        let later = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 3600))
        let started = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-9 * 60))
        let cal = Calendar.current
        let sunrise = ISO8601DateFormatter().string(from: cal.date(bySettingHour: 6, minute: 28, second: 0, of: Date()) ?? Date())
        let sunset = ISO8601DateFormatter().string(from: cal.date(bySettingHour: 16, minute: 48, second: 0, of: Date()) ?? Date())
        let json = """
        {"generatedAt":"x","services":[],
         "today":[{"id":"1","at":"\(soon)","title":"Volleyball at the Y"},{"id":"2","at":"\(later)","title":"Study block: written test"}],
         "offers":{"greeting":"Late night, Dylan. You have volleyball soon and a study block after, and I am rewriting the reminder code in the background.","offers":[]},
         "home":{"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"heat","detail":"heating","current":68,"target":70},
            {"id":"a","name":"Entrance","kind":"light","state":"on"},{"id":"b","name":"Hall","kind":"light","state":"off"},
            {"id":"e","name":"Desk","kind":"light","state":"on","brightness":0.6},
            {"id":"c","name":"Living Room TV","kind":"media","state":"playing","detail":"Netflix"},
            {"id":"f","name":"Bedroom speaker","kind":"media","state":"playing","detail":"Lo-fi beats"},
            {"id":"d","name":"Dylan asleep","kind":"switch","state":"off"}],
          "readings":[{"id":"r1","name":"Balcony door","kind":"door","value":"open"},
            {"id":"r2","name":"Porch sensor","kind":"battery","value":"12","unit":"%"},
            {"id":"r3","name":"Bedroom","kind":"temperature","value":"70.5","unit":"°F"},
            {"id":"r4","name":"Bedroom","kind":"humidity","value":"44","unit":"%"},
            {"id":"r5","name":"Living room","kind":"temperature","value":"68.2","unit":"°F"}],
          "weather":{"condition":"cloudy","temperature":58,"unit":"°F","humidity":72,"wind":6,"windUnit":"mph"},"sun":{"rising":"\(sunrise)","setting":"\(sunset)"}},
         "jobs":{"running":[{"id":"j1","label":"Changing my code so reminders repeat","state":"running","startedAt":"\(started)"}]},
         "cloud":{"health":{"yesterday":{"steps":9580},"sleep":{"asleep_min":422}},
                  "money":{"netWorth":1}}}
        """
        return try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }
}
#endif
