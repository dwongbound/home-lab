# Jarvis for iPhone and iPad

A native SwiftUI front end for the Jarvis running on the lab PC. The brain,
tools and approvals stay on the PC; the app talks to the home page server
at `https://jarvis.snakebird-ph.ts.net` over Tailscale, the same front door
the web page uses. Plan: the "Jarvis iPhone and iPad app" doc in the
project.

It is private: installed through TestFlight internal testing (no App
Review) or straight from Xcode. It never goes to the App Store.

## What's in it (milestone 1)

- **Chat:** history, streaming replies with the model chip ("Jarvis (C)"
  orange, "Jarvis (O)" blue), typing dots and the working label, approval
  cards (Approve/Deny), and the faint "…" for "That was wrong".
- **Today:** Jarvis's greeting and offers (Hide/Start), the agenda, weather
  and thermostat, service alerts, background work.
- **Talk:** hands-free voice, like the page's `/talk`: the orb, what he
  heard and what he's saying, Talk/Pause and Mute, approval cards. Opening
  the tab the first time starts the call. Keeps going with the screen
  locked (background audio); Apple's voice processing cancels his voice out
  of the mic. Pause dozes when Jarvis supports "Hey Jarvis", else hangs up.
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

Builds last 90 days. Automatic uploads from CI come in milestone 5.

## The phone's side

- Tailscale must be connected. Turn on **VPN On Demand** in the Tailscale
  app so it reconnects by itself.
- No login: `tailscale serve` adds your Tailscale login to each request.
- Every request sends `x-home-lab: 1` and an `Origin` matching the server,
  which the Talk socket (`server/talk.mjs`) checks.
