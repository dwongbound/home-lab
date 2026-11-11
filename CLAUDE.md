# home-lab — quick map

Dense index so you can jump straight to files. Conventions and rationale
live in `.claude/CLAUDE.md`. The README is the human-facing guide.

## Stack (verified against package.json)

React **19** · TypeScript **5.9** · Vite **6** · SWR **2** · plain CSS ·
Node server on `node:http` (no framework) · Vitest **3** + jsdom ·
Playwright **1.63** (desktop + Pixel 7 + iPad Pro 11 landscape) · Node **20.12+**.

## Commands

- Dev: `npm run dev` → http://localhost:5180 (API mounted into Vite)
- Prod: `npm run build && npm start` → http://127.0.0.1:4180
- Preview build with no server: `npm run build:preview` → `dist-preview/`
- `npm run typecheck` · `npm run test:unit` · `npm run test:e2e` · `npm test`

## Where things are

- **API:** `server/app.mjs` — `GET /api/snapshot`, `POST /api/actions/:name`
  (`ollama-unload`, `ollama-load`; needs header `x-home-lab: 1`; one at a time, 409 otherwise),
  `POST /api/jarvis/ask` (`{text}`, same header; forwards `Tailscale-User-Login` to Jarvis `/ask`),
  `POST /api/jarvis/chat` (`{text}`, same header; streams Jarvis `/chat/stream` NDJSON), `GET /api/jarvis/history` (Jarvis `/chat/history`), `POST /api/jarvis/warm` (same header; Jarvis `/chat/warm`, sent when the chat sheet opens),
  `POST /api/jarvis/approve` (`{id, ok}`, same header; Jarvis `/approve`) + `GET /api/jarvis/approvals` (Jarvis `/approvals`): Approve/Deny cards for `approval`/`approval_done` events on the chat stream and talk line (`ApprovalCard` in `JarvisPanel`),
  `GET /api/jarvis/memory` + `GET /api/jarvis/memory/search?q=` + `POST /api/jarvis/memory` (`{op: remember|forget}`, same header; Jarvis `/memory/facts`, `/memory/search`; `MemoryPanel` = Memory, last on Settings),
  `GET`/`POST /api/jarvis/voice` + `GET /api/jarvis/voice/sample` (WAV; checks in `server/voice.mjs`; Jarvis `/voice`, `/voice/sample`; `VoicePanel` on Settings before Memory),
  `POST /api/home/control` (`{entity, command, value?}`; climate takes `target` °/`mode`; same header + Tailscale login; allowlist in
  `server/sources/home.mjs`, which also reads devices/weather/sun into `snapshot.home`),
  `POST /api/digest/refresh` (same header; asks Jarvis `/digest/refresh`; client hook `src/api/digestRefresh.tsx`),
  `POST /api/money/picks` (`{op: pick|clear|remind}`, same header; store `server/money-picks.mjs`, file `money-picks-file.mjs`,
  `MONEY_PICKS_FILE`; snapshot `moneyPicks`; banner via `pickReminderDue`).
- **Today:** live `today` = Jarvis `GET /schedule/today`; Overview merges it with the calendar in `src/lib/agenda.ts`. Service alerts go in `AlertBanner` (every page) via `activeAlerts`.
- **Talk:** `server/talk.mjs` proxies the `/api/jarvis/talk` WebSocket (wired in `server/index.mjs`) to Jarvis `/talk/ws?chat=web` (Tailscale login + same-origin `Origin`);
  client `src/lib/talk.ts` (worklet resamples mic to 16 kHz PCM16, plays his PCM, sends `idle`; `partial` events = live words while you talk). Mock data → demo loop.
  Full-screen, voice-only Talk page at `/talk` (or `#talk`; starts talking on load, or on the first tap where iOS needs one via `canTalkUnprompted`; one Talk/Pause button, no typing, no Close): `src/views/TalkPage.tsx` (picked in `src/main.tsx` via `src/lib/talkPage.ts`), `JarvisPanel page`, own `public/talk.webmanifest`.
- **Shell:** `server/shell.mjs` proxies `/shell/` (HTTP + WebSocket upgrade, wired in `server/index.mjs`)
  to ttyd on 127.0.0.1:7681 (`deploy/ttyd.service`, tmux) only for `SHELL_USERS` Tailscale logins with a same-origin `Origin`.
- **Sources:** `server/sources/mock.mjs` (default; Pacific-time schedule, remembers
  the local model loaded/unloaded), `server/sources/live.mjs` (parallel probes, 2.5 s timeouts).
  Picked by `DATA_SOURCE` in `server/app.mjs createSource`.
- **Config/env:** `server/config.mjs` (`loadConfig`, `loadEnvFile`). All vars in `.env.example`.
- **Shape:** `src/types.ts` `Snapshot`, `DataSource`. Change it → update BOTH sources.
- **Page data:** `src/api/client.ts` `useSnapshot()` (SWR, 15 s), `runAction()`.
  `VITE_DATA=static` swaps in the in-browser mock via dynamic import.
- **Cloud digest:** `server/sources/digest.mjs` reads `digest.json` from the private
  `DIGEST_REPO` with `DIGEST_TOKEN` (2 min cache; written every 15 min); shape `CloudDigest` in `src/types.ts`;
  panels in `src/components/CloudPanels.tsx`; the scheduled task's prompt + setup in `docs/digest.md`.
- **Details:** rows link to `#<view>/<kind>/<id>` (`useHashDetail`, `detailHref`, `closeDetail` in
  `src/useHashView.ts`); `src/components/DetailDialog.tsx` is the fixed-size pop-up. Every pop-up calls `useScrollLock` (page behind stays put) and sits inside the iPhone safe area (`.dialog` insets, `--safe-h`). Money's are in
  `src/views/Money.tsx` (`t`, `a`, `c`, `sort`; rules in `src/lib/money.ts`), agenda ones in
  `src/components/AgendaDetail.tsx` (`j`, `e`, `m`).
- **Always-on iPad:** `src/useWakeLock.ts` + Settings switch (`home-lab:v1:awake` in `prefs.ts`);
  `public/manifest.webmanifest` + Apple meta tags in `index.html`. Overview one-screen layout keys off
  `.shell[data-view='overview']` (end of `styles.css`). Swipe tabs: `src/useSwipeNav.ts` (finger-follow + glide in `src/swipeMotion.ts`, `main[data-swipe]`; swipes always slide via `swipeToView`). WebKit skips
  view transitions (its snapshots drop backdrop-filter) and uses `html[data-enter]` panel slides (translate only) (`useHashView.ts`).
- **Views:** `src/views/{Overview,Home,Claude,Money,Services,Schedule,Settings}.tsx`, chosen by
  `src/useHashView.ts` from `#hash`. Nav in `src/components/TopNav.tsx` (`VIEWS`).
- **Components:** `src/components/` — `StatCard` + `Sparkline`, `RequestsChart`,
  `Timeline`, `ActivityList`, `ServicesPanel`, `ModelCard` + `ConfirmDialog`,
  `JarvisPanel` (Ask Jarvis bar + chat sheet + Talk; `JarvisOrb`, `src/lib/talk.ts`), `LoadedModels` (Services: every Ollama model + role, `snapshot.models`), `TerminalPanel` (Services only; the Shell tab was removed 2026-11-11), `MemoryPanel` (Settings: Jarvis's facts + search), `VoicePanel` (Settings: Kokoro voice, speed, blend), `Spinner`, `ThinkingLoader` (first load), `Backdrop`, `Icon`.
- **Helpers:** `src/lib/format.ts`, `sky.ts` (phase by hour), `sparkline.ts`,
  `prefs.ts` (localStorage key `home-lab:v1:sky`, guarded).
- **Styles:** `src/styles.css` — tokens in `:root`, sky phases on `.backdrop[data-phase]` (colours are `@property`-registered so phases fade over 120 s; `data-picked` = 1.5 s),
  ALL animation inside `@media (prefers-reduced-motion: no-preference)` (tested).
  Below-the-screen panels fade in when first scrolled to: `src/useReveal.ts` sets `.glass[data-reveal=wait|in|shown]` (IntersectionObserver, time-based; no `animation-timeline`, which Safari skipped and which restarted after the landing).
- **Tests:** `tests/unit/*` (Vitest), `tests/e2e/dashboard.spec.ts` (Playwright).
  `tests/unit/helpers.ts callApi` drives the handler without a port.
- **Deploy:** `deploy/home-lab.service` (systemd on jarvis) or `Dockerfile` +
  `docker-compose.yml` (host network, 127.0.0.1:4180, published by `tailscale serve` on https 443), CI in `.github/workflows/ci.yml`
  (its `merge` job rebase-merges a passing non-draft PR into `dev`, then it and
  `promote` fast-forward `main` to `dev`).

## The PC

jarvis: Windows 11 + Ubuntu 24.04 in WSL 2 (user `dwong`, systemd on, mirrored
networking), 16 GB RAM (WSL capped at 10), RTX 3060 12 GB. Home Assistant in
Docker at 192.168.68.94:8123. Ollama with ornith-1.5:9b as Jarvis's local model (~6.5 GB VRAM, 20-min keep-alive while he's awake; picked over Qwen 3.5 9B by a 40-item watch benchmark, 2026-11-11).
This page at https://jarvis.snakebird-ph.ts.net, Jarvis agent at :8443 (Open WebUI removed 2026-11-11)
(systemd unit `jarvis`; `sudo -n systemctl restart jarvis` works without a password).

**Never** open, read or print `~/jarvis/data/memory.md` or
`/srv/open-webui/data/webui.db` unless Dylan asks in that conversation.
