# home-lab — quick map

Dense index so you can jump straight to files. Conventions and rationale
live in `.claude/CLAUDE.md`. The README is the human-facing guide.

## Stack (verified against package.json)

React **19** · TypeScript **5.9** · Vite **6** · SWR **2** · plain CSS ·
Node server on `node:http` (no framework) · Vitest **3** + jsdom ·
Playwright **1.63** (desktop + Pixel 7) · Node **20.12+**.

## Commands

- Dev: `npm run dev` → http://localhost:5180 (API mounted into Vite)
- Prod: `npm run build && npm start` → http://127.0.0.1:4180
- Preview build with no server: `npm run build:preview` → `dist-preview/`
- `npm run typecheck` · `npm run test:unit` · `npm run test:e2e` · `npm test`

## Where things are

- **API:** `server/app.mjs` — `GET /api/snapshot`, `POST /api/actions/:name`
  (`ollama-unload`, `ollama-load`; needs header `x-home-lab: 1`; one at a time, 409 otherwise),
  `POST /api/jarvis/ask` (`{text}`, same header; forwards `Tailscale-User-Login` to Jarvis `/ask`),
  `POST /api/home/control` (`{entity, command, value?}`, same header + Tailscale login; allowlist in
  `server/sources/home.mjs`, which also reads devices/weather/sun into `snapshot.home`).
- **Sources:** `server/sources/mock.mjs` (default; Pacific-time schedule, remembers
  Gemma loaded/unloaded), `server/sources/live.mjs` (parallel probes, 2.5 s timeouts).
  Picked by `DATA_SOURCE` in `server/app.mjs createSource`.
- **Config/env:** `server/config.mjs` (`loadConfig`, `loadEnvFile`). All vars in `.env.example`.
- **Shape:** `src/types.ts` `Snapshot`, `DataSource`. Change it → update BOTH sources.
- **Page data:** `src/api/client.ts` `useSnapshot()` (SWR, 15 s), `runAction()`.
  `VITE_DATA=static` swaps in the in-browser mock via dynamic import.
- **Cloud digest:** `server/sources/digest.mjs` reads `digest.json` from the private
  `DIGEST_REPO` with `DIGEST_TOKEN` (2 min cache; written every 15 min); shape `CloudDigest` in `src/types.ts`;
  panels in `src/components/CloudPanels.tsx`; the scheduled task's prompt + setup in `docs/digest.md`.
- **Views:** `src/views/{Overview,Home,Claude,Money,Services,Schedule,Settings}.tsx`, chosen by
  `src/useHashView.ts` from `#hash`. Nav in `src/components/TopNav.tsx` (`VIEWS`).
- **Components:** `src/components/` — `StatCard` + `Sparkline`, `RequestsChart`,
  `Timeline`, `ActivityList`, `ServicesPanel`, `ModelCard` + `ConfirmDialog`,
  `JarvisPanel` (Ask Jarvis), `Spinner`, `Backdrop`, `Icon`.
- **Helpers:** `src/lib/format.ts`, `sky.ts` (phase by hour), `sparkline.ts`,
  `prefs.ts` (localStorage key `home-lab:v1:sky`, guarded).
- **Styles:** `src/styles.css` — tokens in `:root`, sky phases on `.backdrop[data-phase]`,
  ALL animation inside `@media (prefers-reduced-motion: no-preference)` (tested).
- **Tests:** `tests/unit/*` (Vitest), `tests/e2e/dashboard.spec.ts` (Playwright).
  `tests/unit/helpers.ts callApi` drives the handler without a port.
- **Deploy:** `deploy/home-lab.service` (systemd on jarvis) or `Dockerfile` +
  `docker-compose.yml` (host network, 127.0.0.1:4180, published by `tailscale serve` on https 443), CI in `.github/workflows/ci.yml`
  (its `merge` job rebase-merges a passing non-draft PR into `dev`, then it and
  `promote` fast-forward `main` to `dev`).

## The PC

jarvis: Windows 11 + Ubuntu 24.04 in WSL 2 (user `dwong`, systemd on, mirrored
networking), 16 GB RAM (WSL capped at 10), RTX 3060 12 GB. Home Assistant in
Docker at 192.168.68.94:8123. Ollama with Gemma ~12B (~10 GB VRAM, ~3 min load).
This page at https://jarvis.snakebird-ph.ts.net, Open WebUI at :8081, Jarvis agent at :8443
(systemd unit `jarvis`; restarting needs Dylan's sudo password).

**Never** open, read or print `~/jarvis/data/memory.md` or
`/srv/open-webui/data/webui.db` unless Dylan asks in that conversation.
