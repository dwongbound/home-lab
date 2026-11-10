# home-lab

A glassy admin page for **jarvis**, the home lab PC: how much memory, GPU
and disk it's using, whether Home Assistant, Ollama, Open WebUI and the
Jarvis agent are running, what ran today, and a button to unload Gemma
before gaming.

It runs on the PC itself as one small Node process and is reached in a
browser on the PC, a phone or the Mac.

**Stack:** React 19 · TypeScript · Vite 6 · SWR · plain CSS (no UI
framework) · a framework-free Node server (`node:http`) · Vitest (unit) ·
Playwright (end-to-end, desktop and phone)

![The overview at dusk, on sample data](docs/overview-desktop.png)

> **Status:** the page runs on **sample data** today. The live source that
> reads the real PC is written and unit-tested with fakes, but hasn't been
> switched on on jarvis yet. See [Going live](#going-live).

---

## Contents

- [Quick start](#quick-start)
- [What's on the page](#whats-on-the-page)
- [How it fits together](#how-it-fits-together)
- [The data layer](#the-data-layer)
- [Environment variables](#environment-variables)
- [Running it on jarvis](#running-it-on-jarvis)
- [Reaching it from your phone or Mac](#reaching-it-from-your-phone-or-mac)
- [Going live](#going-live)
- [Testing](#testing)
- [Design](#design)
- [Project layout](#project-layout)
- [Working on it](#working-on-it)
- [Privacy](#privacy)

---

## Quick start

Needs Node 20.12 or later (`node -v`).

```bash
npm install

# Dev server with hot reload, sample data:
npm run dev
# → http://localhost:5180

# Production build + server, the way it runs on jarvis:
npm run build
npm start
# → http://127.0.0.1:4180
```

Nothing else is needed for sample data: no `.env`, no token, no PC.

## What's on the page

Four pages, picked from the pill bar at the top. Each is a plain link to a
`#hash`, so the back button, bookmarks and the keyboard all work.

| Page | What it shows |
| --- | --- |
| **Overview** (`#overview`) | A greeting that follows the clock and a line saying how many things need you. Four cards: memory (of 16 GB), GPU memory (of the RTX 3060's 12 GB), processor, and free space on C:, each with a sparkline. **Ask Jarvis**, a box for talking to Jarvis (below). A bar chart of Jarvis requests this week with today lit in blue. Today's runs (the 9 am fantasy pickup run and friends). Recent activity, newest first. Services. The Gemma card. |
| **Claude** (`#claude`) | Your Claude project threads grouped as waiting on you, working, ready for review and finished, each linking to the thread, plus the latest deploys and open PRs. From the [cloud digest](#cloud-digest). |
| **Services** (`#services`) | Every service with its status, response time and a link to open it, the Gemma card, and how to restart Jarvis (it needs your password, so the page can't). |
| **Schedule** (`#schedule`) | Today's runs on jarvis next to your calendar for the day, then email that needs you and recent activity. Calendar and email come from the [cloud digest](#cloud-digest). |
| **Settings** (`#preferences`) | The sky behind the page (follow the clock, or pin dawn, day, dusk or night; saved in that browser only) and where the data is coming from. |

### The Gemma button

Gemma holds about 10 of the GPU's 12 GB. **Unload Gemma** asks first, in a
dialog with **Close** and **Unload**. While Ollama works, the dialog is
blocked: both buttons are disabled, Esc does nothing and a spinner says
what's happening. When it's done the dialog closes and a toast says
"Gemma unloaded". **Load Gemma** brings it back (about 3 minutes).

Only one action runs at a time: the server answers `409` to a second one.

### Ask Jarvis

Type a question and Jarvis answers in the panel, through the same `/ask`
endpoint the Siri Shortcut uses, so it has the same memory, tools and
Home Assistant access. The page keeps that visit's questions and answers
until you reload; Jarvis keeps its own memory.

The page holds no Jarvis password. Jarvis decides who may ask: the server
passes on the `Tailscale-User-Login` header that `tailscale serve` adds,
and Jarvis checks it against `JARVIS_TAILSCALE_USERS`. So Ask Jarvis only
works when the page is opened through Tailscale (see [Reaching it](#reaching-it-from-your-phone-or-mac));
opened at `http://127.0.0.1` it says so instead of answering.

### States every page handles

- **First load:** a blocking spinner, "Reading jarvis…", until the first
  snapshot arrives.
- **Server unreachable:** a panel saying what's wrong and how to fix it,
  with **Try again**.
- **A refresh fails after data has loaded:** the page keeps the last
  numbers and says when they're from.
- **A service reports nothing:** its card says "Not reporting" and lists
  are replaced with a sentence saying what will appear there.

## How it fits together

```
 Browser (PC, phone, Mac)                     jarvis (WSL Ubuntu)
 ┌───────────────────────────┐   GET /api/snapshot every 15 s
 │ React page (src/)         │ ─────────────────────────────────▶ ┌──────────────────────────┐
 │  useSnapshot()  ── SWR    │                                    │ server/index.mjs         │
 │  runAction()              │ ◀───────────────────────────────── │  static files from dist/ │
 └───────────────────────────┘   one JSON Snapshot                │  server/app.mjs  (API)   │
                                                                  │    └ a data source:      │
                                                                  │       mock.mjs | live.mjs│
                                                                  └──────────┬───────────────┘
                                                                             │ (live only, in parallel,
                                                                             │  2.5 s timeout each)
                     nvidia-smi · statfs /mnt/c · os.* · systemctl is-active jarvis
                     Home Assistant /api/ (with the token) · Ollama /api/ps
                     Open WebUI · Jarvis 127.0.0.1:8765/health
```

- **One call per refresh.** Everything the page shows comes back from
  `GET /api/snapshot` as one object, so there's no chain of requests
  waiting on each other. SWR shares that one request between every
  component that needs it and refetches every 15 seconds and when the tab
  regains focus.
- **Dev and prod run the same API code.** `npm run dev` mounts
  `server/app.mjs` into Vite as middleware; `npm start` mounts it into
  `server/index.mjs`. There's no second fake API to keep in step.
- **Secrets stay on the server.** The Home Assistant token is read from
  the environment by `server/config.mjs`, sent only to Home Assistant, and
  never included in a response. A unit test checks this.
- **Actions need a header.** `POST /api/actions/*` and `POST /api/jarvis/ask` are refused without
  `x-home-lab: 1`. A cross-site form can't set a custom header, so another
  web page can't trigger actions on the PC.

## The data layer

The page and the server agree on one shape, `Snapshot`, defined in
[`src/types.ts`](src/types.ts). Both sources produce it:

| Source | File | When | What it does |
| --- | --- | --- | --- |
| Mock | `server/sources/mock.mjs` | `DATA_SOURCE` unset or `mock` (default) | Believable numbers for jarvis. Times are on the PC's Pacific clock. Remembers whether Gemma is loaded so the buttons visibly work. |
| Live | `server/sources/live.mjs` | `DATA_SOURCE=live` | Reads the real PC. Each probe runs in parallel with a 2.5 s timeout; one that fails shows as "Not responding" or "Not reporting" instead of failing the page. |

A source is two functions:

```ts
interface DataSource {
  snapshot(): Promise<Snapshot>                       // GET /api/snapshot
  action(name: 'ollama-unload' | 'ollama-load'): Promise<{ ok: boolean; message: string }>
}
```

### What the live source reads

| On the page | Where it comes from |
| --- | --- |
| Memory | `os.totalmem()` / `os.freemem()` (this is WSL's memory, capped at 10 GB in `.wslconfig`) |
| GPU memory | `nvidia-smi --query-gpu=memory.used,memory.total` (WSL's copy at `/usr/lib/wsl/lib/nvidia-smi`) |
| Processor | `os.cpus()` busy time since the last refresh |
| Free on C: | `statfs('/mnt/c')` |
| Home Assistant | `GET $HA_URL/api/` with `Authorization: Bearer $HA_TOKEN`. A 401 shows as "Needs attention. Token rejected". |
| Ollama and Gemma | `GET $OLLAMA_URL/api/ps` (which models are in memory) |
| Open WebUI | `GET $OPEN_WEBUI_URL`. Any answer below 500 counts as up. |
| Jarvis | `GET $JARVIS_API_URL/health`, which says which brain Jarvis is using ("Thinking with claude"), plus `systemctl is-active jarvis` where there is a systemctl. Answering is "Running"; silent while systemd says active is "Needs attention"; anything else is "Not responding". In Docker there's no systemctl, so `/health` alone decides. |
| Ask Jarvis | `POST $JARVIS_API_URL/ask` with `{"text": ...}` and the caller's `Tailscale-User-Login`, waiting up to 3 minutes. |
| Unload / load Gemma | `POST $OLLAMA_URL/api/generate` with `keep_alive: 0` (unload now) or `OLLAMA_KEEP_ALIVE` (load; `-1`, the default, keeps it loaded forever, which is how jarvis runs Gemma). Ollama has no separate unload call. |
| Requests chart, Today, Recent activity | **Not available yet.** Jarvis doesn't publish these, so the live source returns empty lists and the page shows its empty states. Adding a small `/stats` endpoint to Jarvis is the next step. |

Sparkline history is kept in the server's memory (the last 24 samples, one
per snapshot), so it starts empty after a restart and fills in over a few
minutes.

### Adding a panel

1. Add the field to `Snapshot` in `src/types.ts`.
2. Fill it in **both** `mock.mjs` and `live.mjs`.
3. Build the component in `src/components/` and place it in a view in
   `src/views/`.
4. Add a unit test for the source and, if it's interactive, an end-to-end
   test in `tests/e2e/`.

## Cloud digest

Claude project threads, today's calendar, email needing you, deploys and
open PRs can't be read from the PC: they live in claude.ai and its
connectors. A scheduled Claude task collects them hourly from 7 am to 11 pm
into `digest.json` in a private repo, and the server reads it with a
read-only token (cached 5 minutes, last good copy kept if GitHub is down).
Each panel says how old the digest is.

Setup, the file's shape and the task's prompt are in
[docs/digest.md](docs/digest.md). Without `DIGEST_TOKEN` the panels say
they aren't set up yet, and everything else works as before.

## Environment variables

Copy `.env.example` to `.env` (gitignored). The server loads it at startup
with Node's built-in loader; anything already set in the environment wins.
Point `HOME_LAB_ENV_FILE` at another file to use that instead.

| Variable | Default | What it's for |
| --- | --- | --- |
| `DATA_SOURCE` | `mock` | `live` reads the real PC. |
| `HOST` | `127.0.0.1` | Interface to listen on. `0.0.0.0` to reach it from other devices. |
| `PORT` | `4180` | Port for `npm start`. (`npm run dev` uses 5180.) |
| `HA_URL` | `http://192.168.68.94:8123` | Home Assistant. |
| `HA_TOKEN` | *(empty)* | Home Assistant long-lived access token. **Secret.** Server-side only. |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama's API. |
| `OLLAMA_MODEL` | `gemma4:12b` | The model the Gemma card loads and unloads. Check the exact name with `ollama list`. |
| `OLLAMA_KEEP_ALIVE` | `-1` | How long Load keeps Gemma. `-1` = forever, a number = seconds, or `30m` style. |
| `NVIDIA_SMI` | `/usr/lib/wsl/lib/nvidia-smi` | WSL's nvidia-smi, which isn't on PATH. |
| `OPEN_WEBUI_URL` | `https://jarvis.snakebird-ph.ts.net` | Open WebUI, for its status and link. |
| `JARVIS_URL` | `https://jarvis.snakebird-ph.ts.net:8443` | Jarvis's address on the tailnet, for the link on its row. |
| `JARVIS_API_URL` | `http://127.0.0.1:8765` | Jarvis's own API on the PC, for `/health` and Ask Jarvis. |
| `JARVIS_UNIT` | `jarvis` | The systemd unit to ask about (skipped in Docker, which has no systemctl). |
| `DIGEST_REPO` | `dwongbound/home-lab-digest` | Private repo holding the cloud digest. |
| `DIGEST_BRANCH` | `main` | Its branch. |
| `DIGEST_PATH` | `digest.json` | The file in it. |
| `DIGEST_TOKEN` | *(empty)* | Fine-grained GitHub token, **Contents: Read-only on that one repo**. **Secret.** Empty turns the cloud panels off. |
| `WINDOWS_DRIVE` | `/mnt/c` | Where WSL mounts C:. |
| `HOME_LAB_ENV_FILE` | `.env` | Which env file to load. |
| `VITE_DATA` | *(unset)* | Build-time only. `static` builds the serverless preview (below). |

### The serverless preview

`npm run build:preview` writes `dist-preview/`, a copy of the page that
runs the mock source inside the browser, so it can be opened from any
static host with no server. The normal build never includes the mock data.

## Running it on jarvis

The PC runs Ubuntu 24.04 in WSL 2 with systemd on, and Ubuntu is started at
boot by the "Start Ubuntu (WSL)" task, so a systemd service is enough to
keep the page up across reboots.

```bash
# In Ubuntu on jarvis, as dwong:
git clone https://github.com/dwongbound/home-lab ~/home-lab
cd ~/home-lab
npm ci
npm run build
cp .env.example .env        # then edit .env (see "Going live")
npm start                   # check it, then Ctrl+C

# Run it as a service (needs your password once):
sudo cp deploy/home-lab.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now home-lab
systemctl status home-lab
```

### In Docker

The other way to run it, with nothing installed on Ubuntu but Docker
(which jarvis already has for Home Assistant and Open WebUI):

```bash
cd ~/home-lab
cp .env.example .env        # then edit .env (see "Going live")
docker compose up -d --build
curl -s http://127.0.0.1:4180/api/snapshot | head -c 300
```

`docker-compose.yml` sets `DATA_SOURCE=live`, `HOST=127.0.0.1` and
`PORT=4180`, whatever `.env` says. It uses host networking, so Ollama, Jarvis
and Home Assistant answer at the same addresses as outside the container,
and mounts `/mnt/c` and WSL's `nvidia-smi` read-only for the disk and GPU
cards. `restart: unless-stopped` brings it back after a reboot, once
Docker is up. **Updating:** `git pull && docker compose up -d --build`.

The unit caps the process at 200 MB (`MemoryMax`), since Gemma needs the
RAM more. It typically uses well under 100 MB.

**Updating:** `cd ~/home-lab && git pull && npm ci && npm run build && sudo systemctl restart home-lab`.

## Reaching it from your phone or Mac

By default the server only listens on `127.0.0.1`, which is the PC itself.
The way to open it from other devices is `tailscale serve`, the same way
Jarvis and Open WebUI are published. It works for both the Docker and the
systemd setup, and it's what makes Ask Jarvis work, because it tells the
page (and so Jarvis) who you are. From Ubuntu:

```bash
"/mnt/c/Program Files/Tailscale/tailscale.exe" serve --bg --https=8080 http://127.0.0.1:4180
```

Then open `https://jarvis.snakebird-ph.ts.net:8080` on the phone or Mac
with Tailscale on. `tailscale.exe serve status` lists what's published;
`serve --https=8080 off` takes it down.

Two things that don't work on jarvis, so you don't have to find out:

- **Publishing on the same port the page listens on.** WSL's mirrored
  networking shares ports between Ubuntu and Windows, and `serve --http=80`
  in front of a page on `127.0.0.1:80` never answered (connection refused).
  Every service here uses two numbers (Open WebUI 3000 → 443, Jarvis
  8765 → 8443); keep to that.
- **Plain `http://jarvis.snakebird-ph.ts.net` on port 80.** Open WebUI
  already answers `https://` on that name, and browsers try `https://`
  first, so they land on Open WebUI. Use an `https://` port.

**Without `tailscale serve`**, for the page only (Ask Jarvis won't work):

1. Set `HOST=0.0.0.0` in `.env` and restart the service.
2. WSL uses **mirrored networking**, so Windows' Hyper-V firewall has to
   allow the port. In PowerShell **as Administrator** on Windows:

   ```powershell
   New-NetFirewallHyperVRule -Name "home-lab" -DisplayName "home-lab 4180" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 4180
   ```

3. Open `http://jarvis.snakebird-ph.ts.net:4180` on the phone or Mac with
   Tailscale on.

There's no login on the page. It relies on Tailscale for who can reach it,
the same way Open WebUI does. Don't expose it to the internet, and with
Ask Jarvis don't use `HOST=0.0.0.0` either: anyone on the home network
could then send a made-up Tailscale login header and talk to Jarvis.

## Going live

1. Make a Home Assistant long-lived access token: HA → your profile →
   **Security** → **Long-lived access tokens** → **Create token**. Put it
   in `.env` as `HA_TOKEN=`. (Or point `HOME_LAB_ENV_FILE` at a file that
   already holds it.)
2. Check the model name with `ollama list` and set `OLLAMA_MODEL` to match.
3. Set `DATA_SOURCE=live` and restart: `sudo systemctl restart home-lab`
   (Docker sets it for you; `docker compose up -d` again picks up `.env` changes).
4. Open the page. "Sample data" disappears from the top bar, and Settings →
   Data says "Reading live from jarvis".
5. If a card says "Not reporting" or a service "Not responding", run the
   matching probe by hand (see [What the live source reads](#what-the-live-source-reads)),
   for example `nvidia-smi` or `curl -s http://127.0.0.1:11434/api/ps`.

## Testing

```bash
npm run typecheck     # tsc, no emit
npm run test:unit     # Vitest + jsdom, ~2 s
npm run test:e2e      # Playwright: builds, starts the real server, tests desktop + phone
npm test              # unit, then end-to-end
```

The first time on a new machine, install the browser for end-to-end tests:
`npx playwright install chromium`.

**Unit tests** (`tests/unit/`) cover the text helpers, the sky phases and
sparkline maths, the mock source (including Pacific time across daylight
saving), the live source with every probe faked (status rules, failures
that mustn't break the page, the token sent as a bearer header, the Ollama
call), the API handler (routes, the action header, one action at a time,
the token never in a response), the page itself (first-load spinner, error
state, the Unload flow with its blocking indicator, Close, hash routing),
and a check that every CSS animation sits inside the reduced-motion guard.

**End-to-end tests** (`tests/e2e/`) run each user story on a desktop
browser and a Pixel 7-sized phone against the production server on sample
data: the overview, moving between pages with the back button, unloading
and reloading Gemma, Close and Esc, the remembered sky, no animation with
reduced motion, and no sideways scrolling.

Everything passes on any machine with Node 20.12+; nothing depends on the
PC. CI (`.github/workflows/ci.yml`) runs the same commands on every push
and pull request.

**Auto-merge to main.** When a pull request into `dev` passes, CI's
`merge` job merges it straight away with a rebase, deletes its branch, and
moves `main` up to `dev`. A push to `dev` you make yourself (merging a PR
by hand, say) reaches `main` the same way once its tests pass (`promote`
job). Nothing needs a click. It only merges the exact commit that passed, so
a push made while tests run waits for its own run. To hold a PR back, open
it as a draft (or convert it), and mark it ready when you want it in.
`main` only ever fast-forwards to `dev`: if someone commits to `main`
directly, the next promotion fails instead of overwriting it.

## Design

The look follows the reference screenshot: frosted panels over a blurred
photo, a pill nav, stat cards with sparklines, a bar chart and a "Today"
timeline. Built with Anthropic's *frontend-design* skill and Vercel's
*React best practices* skill.

**The one flourish** is the backdrop: a painted view out of a window that
follows the real time of day on the PC (dawn, day, dusk, night). It's pure
CSS and one static SVG, so it costs nothing to keep on screen. Everything
in front of it stays quiet.

### Tokens (`src/styles.css`, `:root`)

| Token | Value | Used for |
| --- | --- | --- |
| `--basalt` | `#16212c` | The room: page base, the glass fallback, dark text on light buttons |
| `--frost` | `#f2efe9` | Text and primary buttons |
| `--glacier` | `#8ec5ea` | The data accent: today's bar, focus rings, Jarvis |
| `--ember` | `#e8b06a` | The sun; warnings, "needs attention", Gemma's ring |
| `--moss` | `#93d6ae` | Running, done |
| `--rose` | `#f0919a` | Failed, not responding |

Type is **Bricolage Grotesque** for headings and numbers and **Figtree**
for everything else, both bundled with the page (no Google Fonts call), so
it looks right offline. Numbers use tabular figures so they don't jitter
on refresh.

Corner radii follow hierarchy: panels 24 px, stat cards 16 px, cards inside
panels 11 px, pills fully round.

### Conventions

These match TapWorship's:

- A dismiss button reads **Close**, never "Cancel".
- Anything waiting on a network call shows a **blocking indicator** with a
  label saying what it's doing.
- **Motion degrades to the plain page.** The one load sequence and the
  spinners live inside `@media (prefers-reduced-motion: no-preference)`;
  without it, everything is simply there. A unit test enforces this.
- Without `backdrop-filter` support, glass falls back to a solid panel.
- Every log is **newest first**.
- Phone button rows are full width at 44 px touch height, confirm on the
  right. Icon-only controls keep a label for screen readers.
- A dialog has a fixed size and doesn't resize with its contents.
- Copy is plain and sentence case, and errors say what to do next.

### React notes

From the Vercel skill, the rules that shaped the code:

- `client-swr-dedup`: one SWR hook, one request, shared by every component.
- `async-parallel`: the live source runs every probe with `Promise.allSettled`.
- `bundle-conditional`: the mock data is a dynamic import used only by the
  serverless preview build.
- `bundle-barrel-imports`: no icon or chart library; icons are a dozen
  inline paths and the chart is CSS.
- `rerender-memo`: cards, chart, timeline and lists are `memo`'d, since the
  page re-renders on every 15-second refresh.
- `rendering-svg-precision`: sparkline coordinates are rounded to one decimal.
- `js-cache-function-results`: `Intl` formatters are built once at module level.

## Project layout

```
server/
  index.mjs            production server: dist/ + the API, node:http only
  app.mjs              the API handler (also mounted into Vite in dev)
  config.mjs           env vars and .env loading
  sources/mock.mjs     sample data source
  sources/live.mjs     real PC source
src/
  main.tsx             entry: fonts, styles, <App />
  App.tsx              page shell and the loading / error / ready states
  types.ts             Snapshot and DataSource, shared by page and server
  api/client.ts        useSnapshot() and runAction(): the page's only door to data
  views/               Overview, Services, Schedule, Settings
  components/          cards, chart, timeline, lists, dialog, nav, backdrop
  lib/                 format, sky, sparkline, prefs (small pure helpers)
  styles.css           all styles; tokens at the top
tests/
  unit/                Vitest
  e2e/                 Playwright (desktop + phone)
deploy/home-lab.service  systemd unit for jarvis
Dockerfile, docker-compose.yml  the Docker setup
```

## Working on it

- Changes land as a pull request against **`dev`**. `dev` → `main` is
  Dylan's call.
- Tests come with every change and pass before merging, on any machine.
- A change to configuration updates `.env.example` and this README in the
  same pull request.
- Every function has a comment saying what it does, and anything unusual
  or worked-around says why. Prefer plain `if` statements over nested
  ternaries, even if it's longer.
- Commit messages: a short subject line, a blank line, then one bullet per
  change naming the files or areas touched.

  ```
  Live GPU and disk probes

  - Read GPU memory from nvidia-smi (server/sources/live.mjs)
  - Free space on C: via statfs /mnt/c
  - Unit tests with faked probes (tests/unit/live-source.test.ts)
  ```

## Privacy

The page only reads what's listed under
[What the live source reads](#what-the-live-source-reads). It never opens
Jarvis's private memory file (`~/jarvis/data/memory.md`) or Open WebUI's
database (`/srv/open-webui/data/webui.db`), and no change should make it.
