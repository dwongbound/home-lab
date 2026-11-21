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
        return build(now: Self.now, sparse: args.contains("-demoSparse"), long: args.contains("-demoLong"))
    }

    /// The sample snapshot at `now` (full, or `sparse` for the near-empty
    /// case). Split out so a test can check it still decodes.
    static func build(now: Date, sparse: Bool, long: Bool = false) -> Snapshot? {
        // `-demoLong`: a greeting too long for its card, to check it scrolls.
        let greeting = long
            ? "Good evening, Dylan. Volleyball is up next at the Y, and after that the CG x SOW rehearsal runs until ten. I finished rewriting the reminder code so repeats work again, the PS5 Pro is back in stock at Target, your thermostat is heating to 70, the bedroom speaker is playing lo-fi, flights to Tokyo in March dropped by eighty dollars, and tomorrow starts with the dentist at nine, so I'd aim for bed by midnight."
            : "Good evening, Dylan. Volleyball is up next and I'm rewriting the reminder code in the background."
        let args = ProcessInfo.processInfo.arguments
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
         "notices":[\(args.contains("-demoLongNotice") ? DemoSnapshot.longNotice + "," : "")
                    {"id":"n0","kind":"heads","title":"⏰ Buy Natalia's Secret Santa gift.","body":"Secret Santa Overflow is Wednesday, November 25th. Tell me once it's bought and I'll stop reminding you.","source":"reminder","created":"\(iso(-1440))","turnId":12},
                    {"id":"n1","kind":"need","title":"Turn off the bedroom lights?","body":"Jarvis wants to run home_service light.turn_off","source":"approval","created":"\(iso(-3))","approvalId":"ap1"},
                    {"id":"n2","kind":"heads","title":"PS5 Pro back in stock at Target","body":"Lookout spotted it 10 minutes ago","source":"lookout","created":"\(iso(-12))"},
                    {"id":"n3","kind":"fyi","title":"Reminder code rewrite finished","body":"Changing my code so reminders repeat: done","source":"job","created":"\(iso(-95))"}],
         "services":[{"id":"h","name":"Home Assistant","detail":"","status":"up"},{"id":"o","name":"Ollama","detail":"","status":"idle"},{"id":"j","name":"Jarvis","detail":"","status":"up"}],
         "today":[{"id":"jarvis-a@0830","at":"\(iso(-300))","title":"Marketplace deal watch","detail":"Jarvis: scan","status":"done"},
                  {"id":"c1","at":"\(iso(-150))","title":"Lunch with Sam"},
                  {"id":"c2","at":"\(iso(42))","title":"Volleyball at the Y"},
                  {"id":"jarvis-b@1900","at":"\(iso(120))","title":"Follow up on dinner plans","detail":"Jarvis: reminder"},
                  {"id":"c3","at":"\(iso(180))","title":"CG x SOW rehearsal"}],
         "offers":{"greeting":"\(greeting)","offers":[{"id":"o1","title":"Draft the rehearsal set list","body":"","startText":""}]},
         "home":{"devices":[{"id":"t","name":"Thermostat","kind":"climate","state":"heat","detail":"heating","current":68,"target":70,"humidity":44},
            {"id":"a","name":"Entrance","kind":"light","state":"on"},{"id":"b","name":"WiZ RGBW Tunable 7C1A2B","kind":"light","state":"off"},
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
         "metrics":[{"id":"ram","value":19.6,"total":32,"history":[17.2,17.8,18.1,18.0,18.6,19.2,19.0,19.4,19.9,19.5,19.6,19.6]},
                    {"id":"gpu","value":10.1,"total":12,"history":[6.2,6.4,9.8,10.0,10.1,9.9,10.2,10.1,10.0,10.1,10.1,10.1]},
                    {"id":"cpu","value":18,"total":100,"history":[12,9,22,35,18,14,27,19,16,21,18,18]},
                    {"id":"disk","value":93,"total":237,"history":[95,95,94.6,94.4,94,93.8,93.6,93.4,93.2,93.1,93,93]}],
         "gpu":{"totalMb":12288,"usedMb":10342,"utilization":37,"users":[{"name":"Ornith","role":"Local brain","mb":6554,"kind":"local"},{"name":"Parakeet","role":"Hears you","mb":2560,"kind":"speech"},{"name":"Kokoro","role":"His voice","mb":1024,"kind":"speech"},{"name":"Everything else","mb":204,"kind":"other"}]},
         "ram":{"totalMb":32768,"usedMb":27650,"scope":"pc","users":[{"name":"Linux file cache","role":"Given back when needed","mb":13800},{"name":"Windows and its apps","role":"Everything on the Windows side","mb":9400},{"name":"Jarvis","role":"The assistant","mb":1950},{"name":"Ollama","role":"Local models","mb":1850},{"name":"Claude sessions","role":"Coding helpers","mb":690},{"name":"Home Assistant","role":"The house","mb":360},{"name":"Docker","role":"Containers","mb":110},{"name":"Home page","role":"This dashboard","mb":45},{"name":"Everything else","role":"Other programs","mb":12}]},
         "disks":[{"id":"c","name":"C: drive","usedGb":231,"totalGb":255,"users":[{"name":"Linux disk file","gb":63},{"name":"Everything else","gb":168}]},
                  {"id":"linux","name":"Linux disk","usedGb":54,"totalGb":1081,"users":[{"name":"Ollama models","gb":12.5},{"name":"Docker","gb":9.8},{"name":"Jarvis data","gb":6.1},{"name":"Speech models","gb":4.2},{"name":"Home page","gb":1.1},{"name":"Logs","gb":0.6},{"name":"Everything else","gb":19.7}]},
                  {"id":"d","name":"D: drive","usedGb":590,"totalGb":1989,"users":[]}],
         \(args.contains("-demoNoSleep") ? "" : #""sleep":\#(DemoSleep.summaryJSON(now: now)),"#)
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

extension DemoSnapshot {
    /// `-demoLongNotice`: a notice with a title over three lines and a body
    /// over two screens, ending "the very last words." (UI tests).
    static var longNotice: String {
        let title = String(repeating: "A long heads-up title that runs on ", count: 5) + "and ends here"
        let body = (1...60).map { "Line \($0) of a long notice body, with enough words to wrap." }.joined(separator: " ") + " The very last words."
        return #"{"id":"nlong","kind":"heads","title":"\#(title)","body":"\#(body)","source":"lookout","created":"2026-11-20T19:00:00-08:00","turnId":77}"#
    }
}

/// Made-up sleep for the simulator: 14 nights ending this morning, with
/// stage timelines. Not anyone's real numbers.
public enum DemoSleep {
    /// The nights, newest first. `-demoSleepFirstNights` leaves out the
    /// consistency part (too few nights yet); `-demoSleepNoVitals` the vitals.
    public static func nights(now: Date) -> [SleepDay] {
        let args = ProcessInfo.processInfo.arguments
        let data = Data("[\(nightsJSON(now: now, firstNights: args.contains("-demoSleepFirstNights"), vitals: !args.contains("-demoSleepNoVitals")))]".utf8)
        return (try? JSONDecoder().decode([SleepDay].self, from: data)) ?? []
    }

    static func summaryJSON(now: Date) -> String {
        let args = ProcessInfo.processInfo.arguments
        let all = nightsJSONList(now: now, firstNights: args.contains("-demoSleepFirstNights"), vitals: !args.contains("-demoSleepNoVitals"), stages: false)
        let trend = (0..<7).map { i in
            let night = SleepNights.key(now.addingTimeInterval(Double(-i) * 86_400))
            return #"{"night":"\#(night)","score":\#(scores[i % scores.count]),"asleep":\#(asleeps[i % asleeps.count])}"#
        }.joined(separator: ",")
        return #"{"last":\#(all[0]),"trend":[\#(trend)]}"#
    }

    private static let scores = [82, 74, 88, 61, 79, 90, 69, 77, 84, 58, 72, 86, 80, 66]
    private static let asleeps = [440, 405, 468, 352, 425, 476, 398, 415, 452, 330, 410, 462, 438, 380]

    static func nightsJSON(now: Date, firstNights: Bool, vitals: Bool) -> String {
        nightsJSONList(now: now, firstNights: firstNights, vitals: vitals, stages: true).joined(separator: ",")
    }

    private static func nightsJSONList(now: Date, firstNights: Bool, vitals: Bool, stages: Bool) -> [String] {
        let f = ISO8601DateFormatter()
        f.timeZone = SleepNights.zone
        return (0..<14).map { i in
            let night = SleepNights.key(now.addingTimeInterval(Double(-i) * 86_400))
            let window = SleepNights.window(night)!
            let asleep = asleeps[i % asleeps.count]
            let bed = window.start.addingTimeInterval(Double(5 * 3600 + (i % 3) * 600))   // about 11 PM
            let wake = bed.addingTimeInterval(Double(asleep + 25) * 60)
            // A plausible pattern of cycles: core, deep, core, REM, a short wake.
            var segs: [String] = []
            var t = bed
            let pattern: [(String, Double)] = [("core", 30), ("deep", 45), ("core", 40), ("rem", 20), ("awake", 6), ("core", 50), ("deep", 25), ("rem", 30), ("core", 60), ("rem", 35), ("awake", 4), ("core", 70), ("rem", 40)]
            for (stage, mins) in pattern where t < wake {
                let end = min(wake, t.addingTimeInterval(mins * 60))
                segs.append(#"{"stage":"\#(stage)","start":"\#(f.string(from: t))","end":"\#(f.string(from: end))"}"#)
                t = end
            }
            if t < wake { segs.append(#"{"stage":"core","start":"\#(f.string(from: t))","end":"\#(f.string(from: wake))"}"#) }
            let score = scores[i % scores.count]
            let band = score >= 85 ? "great" : score >= 70 ? "good" : score >= 50 ? "fair" : "poor"
            let consistency = firstNights ? "null" : "\(18 + i % 10)"
            let vitalsJSON = vitals
                ? #"{"heartRate":{"avg":\#(54 + i % 5),"min":\#(47 + i % 4)},"hrvMs":\#(42 + i % 9),"hrvRmssdMs":null,"respiratoryRate":14.\#(i % 9),"spo2":{"avg":96,"min":\#(91 + i % 3)},"wristTempC":34.5,"wristTempDeltaC":\#(i % 2 == 0 ? "-0.2" : "0.3"),"breathingDisturbances":null}"#
                : "null"
            return #"""
            {"night":"\#(night)","bedtime":"\#(f.string(from: bed))","wake":"\#(f.string(from: wake))",
             "minutes":{"asleep":\#(asleep),"inBed":\#(asleep + 25),"awake":12,"deep":\#(asleep / 6),"rem":\#(asleep / 4),"core":\#(asleep - asleep / 6 - asleep / 4),"unspecified":0},
             "interruptions":\#(1 + i % 3),"vitals":\#(vitalsJSON),
             "score":\#(score),"scoreSource":"jarvis","scoreBand":"\#(band)",
             "scoreParts":{"duration":\#(min(50, asleep * 50 / 450)),"consistency":\#(consistency),"interruptions":\#(firstNights ? "null" : "\(20 - i % 6)")},
             "stages":[\#(stages ? segs.joined(separator: ",") : "")]}
            """#
        }
    }
}
#endif
