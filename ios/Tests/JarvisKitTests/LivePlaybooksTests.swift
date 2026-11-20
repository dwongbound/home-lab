// The live GET /api/jarvis/playbooks on 2026-11-20 (Jarvis build 84, page
// 9cab78a), run through the app's own reader. Scrubbed: devices, scenes and
// TVs are made up; stepTypes, jobs and thinkers are as Jarvis sent them.
import XCTest
@testable import JarvisKit

final class LivePlaybooksTests: XCTestCase {
    static let live = #"""
{
 "book": {
  "playbooks": [
   {
    "id": "arrive-home",
    "name": "Arrive home",
    "enabled": true,
    "purpose": "",
    "whenToUse": "",
    "trigger": {
     "type": "arrive",
     "zone": "home",
     "minAway": 15
    },
    "inputs": [],
    "steps": [
     {
      "type": "app",
      "entity": "media_player.tv",
      "app": "Jarvis"
     }
    ],
    "decisions": [],
    "done": [],
    "edgeCases": [],
    "standard": "",
    "badVersion": "",
    "madeBy": "dylan"
   },
   {
    "id": "nightly",
    "name": "Nightly self-improvement",
    "enabled": true,
    "purpose": "",
    "whenToUse": "Every night after the day's talking is done.",
    "trigger": {
     "type": "time",
     "at": "03:30",
     "days": []
    },
    "inputs": [],
    "steps": [
     {
      "type": "job",
      "job": "nightly"
     }
    ],
    "decisions": [],
    "done": [
     "The day's flagged mistakes were reviewed",
     "The regression eval cases were run and scored",
     "Memory was tidied (new facts filed, duplicates merged)",
     "At most 3 improvement ideas were proposed, each waiting for his OK"
    ],
    "edgeCases": [
     "Self-change proposals still need his OK before anything changes",
     "Never reads data/memory.md and never pushes anything"
    ],
    "standard": "",
    "badVersion": "",
    "madeBy": "dylan"
   }
  ],
  "options": {
   "devices": [
    {
     "entity": "light.desk",
     "name": "Desk lamp",
     "kind": "light",
     "commands": [
      "turn_on",
      "turn_off"
     ]
    },
    {
     "entity": "climate.bedroom",
     "name": "Thermostat",
     "kind": "climate",
     "commands": [
      "set_temperature",
      "set_hvac_mode",
      "turn_off"
     ]
    },
    {
     "entity": "media_player.tv",
     "name": "Living room TV",
     "kind": "media_player",
     "commands": [
      "turn_on",
      "turn_off",
      "volume_set",
      "select_source"
     ]
    }
   ],
   "scenes": [
    {
     "entity": "scene.movie",
     "name": "Movie"
    }
   ],
   "apps": [
    {
     "entity": "media_player.tv",
     "name": "Living room TV",
     "apps": [
      "Jarvis",
      "Netflix"
     ]
    }
   ],
   "zones": [
    "home"
   ],
   "jobs": [
    {
     "id": "nightly",
     "name": "The nightly self-improvement pass (memory, flagged mistakes, evals, tidy-up, ideas)"
    }
   ],
   "thinkers": [
    {
     "id": "worker",
     "name": "Ornith (simple, stays on the PC)"
    },
    {
     "id": "claude",
     "name": "Claude (judgment and writing)"
    }
   ],
   "stepTypes": [
    {
     "type": "device",
     "label": "Control a device",
     "short": "Device",
     "runs": "code",
     "summary": "{entity.name}: {command} {value}",
     "fields": [
      {
       "key": "entity",
       "label": "Device",
       "kind": "choice",
       "required": true,
       "choicesFrom": "devices"
      },
      {
       "key": "command",
       "label": "Do",
       "kind": "choice",
       "required": true,
       "choicesFrom": "devices",
       "dependsOn": "entity",
       "choicesKey": "commands"
      },
      {
       "key": "value",
       "label": "Value",
       "kind": "by_command",
       "required": false,
       "dependsOn": "command",
       "byCommand": {
        "turn_on": {
         "label": "Brightness %",
         "kind": "number",
         "required": false,
         "min": 1,
         "max": 100,
         "onlyDomains": [
          "light"
         ]
        },
        "volume_set": {
         "label": "Volume (0 to 1)",
         "kind": "number",
         "required": true,
         "min": 0,
         "max": 1,
         "step": 0.05
        },
        "select_source": {
         "label": "App or input",
         "kind": "choice",
         "required": true,
         "choicesFrom": "apps",
         "dependsOn": "entity",
         "choicesKey": "apps"
        },
        "set_temperature": {
         "label": "Temperature (°F)",
         "kind": "number",
         "required": true,
         "min": 45,
         "max": 90
        },
        "set_hvac_mode": {
         "label": "Mode",
         "kind": "choice",
         "required": true,
         "choices": [
          "off",
          "heat",
          "cool",
          "heat_cool",
          "auto"
         ]
        }
       }
      }
     ]
    },
    {
     "type": "scene",
     "label": "Run a scene",
     "short": "Scene",
     "runs": "code",
     "summary": "Scene: {entity.name}",
     "fields": [
      {
       "key": "entity",
       "label": "Scene",
       "kind": "choice",
       "required": true,
       "choicesFrom": "scenes"
      }
     ]
    },
    {
     "type": "app",
     "label": "Open an app on a TV",
     "short": "TV app",
     "runs": "code",
     "summary": "Open {app} on {entity.name}",
     "fields": [
      {
       "key": "entity",
       "label": "TV",
       "kind": "choice",
       "required": true,
       "choicesFrom": "apps"
      },
      {
       "key": "app",
       "label": "App",
       "kind": "choice",
       "required": true,
       "max": 80,
       "choicesFrom": "apps",
       "dependsOn": "entity",
       "choicesKey": "apps"
      }
     ]
    },
    {
     "type": "notify",
     "label": "Send me a notification",
     "short": "Notify me",
     "runs": "code",
     "summary": "Notify me: {text}",
     "fields": [
      {
       "key": "text",
       "label": "Message",
       "kind": "longtext",
       "required": true,
       "max": 2000,
       "placeholder": "What to tell me"
      }
     ]
    },
    {
     "type": "think",
     "label": "Have Jarvis work something out",
     "short": "Ask Jarvis",
     "runs": "thinking",
     "summary": "Jarvis: {text}",
     "fields": [
      {
       "key": "text",
       "label": "What Jarvis should do",
       "kind": "longtext",
       "required": true,
       "max": 2000,
       "placeholder": "Check tomorrow's weather and tell me if I need a jacket"
      },
      {
       "key": "model",
       "label": "Who does it",
       "kind": "choice",
       "required": false,
       "default": "claude",
       "choicesFrom": "thinkers"
      },
      {
       "key": "confirm",
       "label": "Ask me first",
       "kind": "bool",
       "required": false,
       "default": false
      }
     ]
    },
    {
     "type": "email",
     "label": "Send an email",
     "short": "Email",
     "runs": "code",
     "summary": "Email {to}: {subject}",
     "fields": [
      {
       "key": "to",
       "label": "To",
       "kind": "emails",
       "required": true,
       "maxItems": 10
      },
      {
       "key": "subject",
       "label": "Subject",
       "kind": "text",
       "required": true,
       "max": 200
      },
      {
       "key": "body",
       "label": "Message",
       "kind": "longtext",
       "required": true,
       "max": 5000
      },
      {
       "key": "confirm",
       "label": "Ask me first",
       "kind": "bool",
       "required": false,
       "default": false
      }
     ]
    },
    {
     "type": "wait",
     "label": "Wait",
     "short": "Wait",
     "runs": "code",
     "summary": "Wait {seconds} s",
     "fields": [
      {
       "key": "seconds",
       "label": "Seconds",
       "kind": "number",
       "required": true,
       "min": 1,
       "max": 600,
       "default": 60
      }
     ]
    },
    {
     "type": "job",
     "label": "Run one of Jarvis's jobs",
     "short": "Jarvis job",
     "runs": "code",
     "summary": "Run: {job.name}",
     "fields": [
      {
       "key": "job",
       "label": "Job",
       "kind": "choice",
       "required": true,
       "choicesFrom": "jobs"
      }
     ]
    }
   ]
  }
 }
}
"""#

    private func book() throws -> (raw: [[String: Any]], options: PlaybookOptions) {
        try XCTUnwrap(Playbooks.book(from: Data(Self.live.utf8)))
    }

    func testEveryLiveKindParsesWithNothingDropped() throws {
        let options = try book().options
        XCTAssertEqual(options.stepTypes.map(\.type), ["device", "scene", "app", "notify", "think", "email", "wait", "job"])
        let sent = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(Self.live.utf8)) as? [String: Any])
            .flatMap { ($0["book"] as? [String: Any])?["options"] as? [String: Any] }?["stepTypes"] as? [[String: Any]])
        for (parsed, raw) in zip(options.stepTypes, sent) {
            XCTAssertEqual(parsed.fields.count, (raw["fields"] as? [Any])?.count, "fields dropped from \(parsed.type)")
        }
        XCTAssertEqual(options.thinkers.map(\.entity), ["worker", "claude"])
        XCTAssertEqual(options.jobs.map(\.entity), ["nightly"])
    }

    func testLiveKindsMatchTheFallbackWhereTheyShould() throws {
        let live = try book().options.stepTypes
        for (l, d) in zip(live, StepTypes.defaults) {
            XCTAssertEqual(l.type, d.type)
            XCTAssertEqual(l.short, d.short)
            XCTAssertEqual(l.summary, d.summary)
            XCTAssertEqual(l.fields.map(\.key), d.fields.map(\.key))
            XCTAssertEqual(l.fields.map(\.rule.kind), d.fields.map(\.rule.kind))
            XCTAssertEqual(l.fields.map(\.rule.required), d.fields.map(\.rule.required))
        }
    }

    func testNightlyReadsWithItsRealNameAndThePickerOffersIt() throws {
        let (raw, options) = try book()
        let nightly = try XCTUnwrap(raw.first { $0["id"] as? String == "nightly" })
        let draft = PlaybookDraft(json: nightly)
        let step = try XCTUnwrap(draft.steps.first)
        XCTAssertTrue(step.sentence(options).hasPrefix("Run: The nightly self-improvement pass"), step.sentence(options))
        let jobField = try XCTUnwrap(options.stepType(of: step)?.fields.first)
        XCTAssertEqual(options.choices(for: jobField.rule, step).map(\.id), ["nightly"])
        XCTAssertNil(draft.problem(options))
        // Opened and saved untouched, it goes back as it came.
        var came = nightly
        came.removeValue(forKey: "madeBy")
        XCTAssertEqual(draft.json as NSDictionary, came as NSDictionary)
    }

    func testEveryKindStartsSensibly() throws {
        let options = try book().options
        for kind in options.stepTypes {
            let step = DraftStep.blank(kind.type, options: options)
            for field in kind.fields {
                guard let rule = options.activeRule(field, step) else { continue }
                if rule.kind == "choice", rule.required {
                    XCTAssertFalse(options.choices(for: rule, step).isEmpty, "\(kind.type).\(field.key) has nothing to pick")
                }
            }
        }
        XCTAssertEqual(options.stepChoices.count, 8, "every kind can be added with these options")
    }
}
