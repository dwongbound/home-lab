# Jarvis for iPhone and iPad

A native SwiftUI front end for the Jarvis running on the lab PC. The brain,
tools and approvals stay on the PC; the app talks to the home page server
at `https://jarvis.snakebird-ph.ts.net` over Tailscale, the same front door
the web page uses. Plan: the "Jarvis iPhone and iPad app" doc in the
project.

It is private: installed through TestFlight internal testing (no App
Review) or straight from Xcode. It never goes to the App Store.

## What's in it (milestone 1)

Three pages, left to right: **Home**, **Talk**, **Chat**. The app opens on
Home; swiping and the tab bar follow that order.

- **Chat:** history, streaming replies with the model chip (orange for
  Claude with its model letter, "Jarvis (CO)" / "(CH)" / "(CS)" / "(CF)";
  "Jarvis (O)" blue), typing dots and the working label, approval
  cards (Approve/Deny), and the faint "…" for "That was wrong".
- **Today:** Jarvis's greeting and offers (Hide/Start), the agenda, weather
  and thermostat, service alerts, background work.
- **Talk:** hands-free voice, like the page's `/talk`: the orb, what he
  heard and what he's saying, Talk/Pause and Mute, approval cards. Opening
  the tab the first time starts the call. Keeps going with the screen
  locked (background audio); Apple's voice processing cancels his voice out
  of the mic. Pause dozes when Jarvis supports "Hey Jarvis", else hangs up.
- **Reports:** Jarvis's HTML reports, read in the app's own reader
  (`App/ReportView.swift`), never Safari: the page is fetched through
  JarvisClient and shown in a WKWebView with JavaScript off; a link to
  another `/reports/{id}` opens in the same reader, anything else does
  nothing. Opened from a "Report ready" notice or push, a chat link to
  `/reports/{id}` on the home page, or the Reports card on Home (snapshot
  `reports`: size, "Deletes Dec 18" / "Kept until you switch Keep off",
  the rule and the room used, a Keep switch and Delete, asked first). Ids
  must be 16 lowercase hex (`JarvisKit/Reports.swift`, wording in step with
  `src/lib/reports.ts`). The TV shows a read-only Reports card and the
  Watch a line, both "Open on your iPhone to read the report".
- **Diet:** the Diet card on Home opens one day's food (`App/DietView.swift`):
  the week's calorie rings (tap a day), calories, protein, fat and carbs
  against their goals, and what was eaten hour by hour. Read-only, from
  `GET /api/jarvis/nutrition/day` and `/week`; the grouping, totals and
  rings are `JarvisKit/Diet.swift`, Pacific time.
- **Settings:** the server address and a connection check.
- The orb (design D: a glass core in a 3D constellation) and the app icon.

## Apple Watch and Apple TV (started 2026-11-16)

- **Watch** (`Watch/`, target `JarvisWatch`, ships inside the iPhone app):
  tap Ask and dictate, see his answer with the model chip, Approve/Deny
  what's waiting. Tailscale doesn't run on watchOS, so every request goes
  through the iPhone app over WatchConnectivity (`App/WatchBridge.swift`,
  messages in `JarvisKit/WatchRelay.swift`). The phone must be nearby; the
  app needn't be open.
- **Apple TV** (`TV/`, target `JarvisTV`): the always-on display. Big orb,
  clock, greeting, agenda, home, background work; refreshes every 15 s and
  keeps the TV awake. Needs Tailscale's Apple TV app signed in.

Next: push notifications, Siri and widgets, the iPad always-on view, a TV icon.

## Layout

| Path | What |
| --- | --- |
| `Package.swift`, `Sources/JarvisKit/` | Chat and Talk events, Talk audio helpers, wording, snapshot, HTTP client. No UI, so `swift test` runs on any Mac. |
| `Tests/JarvisKitTests/` | Unit tests for the above. |
| `App/` | The SwiftUI app: `JarvisApp` (tabs), `ChatView` + `ChatModel`, `TalkView` + `TalkLine` (AVAudioEngine + WebSocket), `TodayView`, `SettingsView`, `ApprovalCard`, `OrbView`, `Theme`. |
| `project.yml` | XcodeGen spec; the `.xcodeproj` is generated, not committed. |
| `scripts/make_icon.py` | Draws the app icon (`python3 scripts/make_icon.py`, needs Pillow). |

## Build and run on your Mac

```sh
brew install xcodegen
cd ios
swift test            # JarvisKit's unit tests
xcodegen              # makes Jarvis.xcodeproj
open Jarvis.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities, choose your iPhone,
and Run. A paid developer account keeps the install for a year.

## TestFlight (one-time setup)

1. In App Store Connect, add an app with bundle id `com.dwongbound.jarvis`.
2. In Xcode, Product > Archive, then Distribute App > TestFlight Internal Only.
3. Install TestFlight on the iPhone and iPad and accept the invite.

### Uploading from the command line

`ios/scripts/upload-testflight.sh` archives and uploads (or pass an existing
`.xcarchive` to upload just that), signed in with an App Store Connect API key
rather than Xcode's account sign-in:

1. In App Store Connect → Users and Access → Integrations → Team Keys, make a
   key with the App Manager role and download `AuthKey_<KEY_ID>.p8`.
2. Move it to `~/.appstoreconnect/private_keys/` and `chmod 600` it.
3. Put `ASC_KEY_ID=…` and `ASC_ISSUER_ID=…` in `ios/scripts/asc.local`
   (git-ignored), or export them.

It uploads for internal testing only and never submits for review. The key
and `asc.local` are in `.gitignore`.

Builds last 90 days. Automatic uploads from CI come in milestone 5.

## The phone's side

- Tailscale must be connected. Turn on **VPN On Demand** in the Tailscale
  app so it reconnects by itself.
- No login: `tailscale serve` adds your Tailscale login to each request.
- Every request sends `x-home-lab: 1` and an `Origin` matching the server,
  which the Talk socket (`server/talk.mjs`) checks.
