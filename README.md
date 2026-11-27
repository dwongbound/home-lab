# home-lab

The server on **jarvis**, the home lab PC, that the native Jarvis apps
(iPhone, iPad, Apple TV, Watch, in `ios/`) talk to. It gathers the PC's
health, Home Assistant, Ollama and the Jarvis agent into one snapshot,
passes chat, Talk and every other app request through to Jarvis, serves
Jarvis's reports, and guards a terminal.

The bare URL, `https://jarvis.snakebird-ph.ts.net/`, is a plain page with
the backend's health: services up or down, graphics card, memory, disks
and running jobs. It has no scripts and reloads every 15 seconds. The old
React web page was retired on 2026-11-26, once the apps could do what it
did.

It runs on the PC as one small Node process with no dependencies
(`node:http` only). Tests are Vitest.

## Quick start

Needs Node 20.12 or later (`node -v`).

```bash
npm install          # only the test tools
npm start            # → http://127.0.0.1:4180, sample data
npm test
```

Nothing else is needed for sample data: no `.env`, no token, no PC.

## Endpoints

Every route is listed in `CLAUDE.md` with its shape. In short:

- `GET /`: the metrics page (`server/metrics-page.mjs`).
- `GET /api/snapshot`: everything the apps show at a glance, as one JSON
  object, built once and shared by every caller for 3 seconds.
- `/api/jarvis/*`, `/api/home/control`, `/api/actions/*`, `/api/money/picks`,
  `/api/digest/refresh`: what the apps do.
- `GET /reports/<id>`: one of Jarvis's reports as a locked-down page.
- `/api/jarvis/talk`: Talk's WebSocket, proxied to Jarvis (`server/talk.mjs`).
- `/shell/`: the terminal (below).


### The terminal

A real terminal on jarvis, as `dwong`, at `/shell/`. It's `tmux new -A -s main`, so it's the same
session every time, and a long command keeps going if your phone locks.

ttyd has no login of its own, so this server is the lock
(`server/shell.mjs`). `/shell/` and its WebSocket get through only when:

1. `SHELL_USERS` is set (empty, the default, means the shell is off),
2. the `Tailscale-User-Login` header that `tailscale serve` adds is one of
   those logins, and
3. any `Origin` is this server itself, so another website open in your
   browser can't use your login to reach the terminal.

ttyd listens on 127.0.0.1 only and runs as a user service
(`deploy/ttyd.service`; setup steps are at the top of that file).

## How it fits together

- **One call per refresh.** Everything an app shows at a glance comes back
  from `GET /api/snapshot` as one object. In live mode it runs about 17
  probes in parallel (nvidia-smi, disks, systemctl, Home Assistant, Ollama,
  Jarvis), each with a 2.5 s timeout, and callers within 3 seconds share one
  build.
- **Secrets stay on the server.** The Home Assistant token is read from
  the environment by `server/config.mjs`, sent only to Home Assistant, and
  never included in a response. A unit test checks this.
- **Home control is a short list.** `POST /api/home/control` takes one
  entity and one of `toggle`, `brightness`, `power`, `playpause`, `volume`,
  `run`, `target` (a temperature) or `mode` (a known HVAC mode), for
  thermostats, lights, switches, fans, media players, scenes and scripts
  only, and makes the one Home Assistant service call it stands for
  (`server/sources/home.mjs`). An app can never name a service, and
  locks, alarms and covers are out of reach. Like Ask Jarvis it needs the
  Tailscale login that `tailscale serve` adds. When on/off goes through but
  Home Assistant reports nothing changed (a device asleep or disconnected,
  like an Apple TV that has lost its connection), the tile says so instead
  of looking like it worked.
- **The Amazon Smart Thermostat** has no official Home Assistant
  integration. It comes in through the community
  [Alexa Thermostat](https://github.com/nikolmedo/AlexaThermostat)
  integration (copied into HA's `custom_components`, signed in to Amazon
  in HA's UI), which makes it an ordinary `climate` entity. Amazon doesn't
  report whether it's heating right now, and it updates once a minute.
- **Actions need a header.** `POST /api/actions/*`, `POST /api/jarvis/ask`, `POST /api/home/control` and `POST /api/digest/refresh` are refused without
  `x-home-lab: 1`. A cross-site form can't set a custom header, so another
  web page can't trigger actions on the PC.

## The data layer

The apps and the server agree on one shape, the snapshot (its Swift side is
in `ios/Sources/JarvisKit`). Both sources produce it:

| Source | File | When | What it does |
| --- | --- | --- | --- |
| Mock | `server/sources/mock.mjs` | `DATA_SOURCE` unset or `mock` (default) | Believable numbers for jarvis. Times are on the PC's Pacific clock. Remembers whether the local model is loaded so the buttons visibly work. |
| Live | `server/sources/live.mjs` | `DATA_SOURCE=live` | Reads the real PC. Each probe runs in parallel with a 2.5 s timeout; one that fails shows as "Not responding" or "Not reporting" instead of failing the page. |

A source is two functions:

```ts
interface DataSource {
  snapshot(): Promise<Snapshot>                       // GET /api/snapshot
  action(name: 'ollama-unload' | 'ollama-load'): Promise<{ ok: boolean; message: string }>
}
```

### What the live source reads

| In the snapshot or API | Where it comes from |
| --- | --- |
| Memory | `os.totalmem()` / `os.freemem()` (this is WSL's memory, capped at 10 GB in `.wslconfig`) |
| GPU memory | `nvidia-smi --query-gpu=memory.used,memory.total` (WSL's copy at `/usr/lib/wsl/lib/nvidia-smi`) |
| Processor | `os.cpus()` busy time since the last refresh |
| Free on C: | `statfs('/mnt/c')` |
| Home Assistant | `GET $HA_URL/api/` with `Authorization: Bearer $HA_TOKEN`. A 401 shows as "Needs attention. Token rejected". |
| Ollama and the local model | `GET $OLLAMA_URL/api/ps` (which models are in memory) |
| Jarvis | `GET $JARVIS_API_URL/health`, which says which brain Jarvis is using ("Thinking with claude") and, on a Jarvis that reports `version` (`{build, hash, dirty, started_at, pending}`), his build number ("build 142", "with unsaved edits", "pending build 143"; build numbers only, no hashes, Dylan 2026-11-16), plus `systemctl is-active jarvis` where there is a systemctl. Answering is "Running"; silent while systemd says active is "Needs attention"; anything else is "Not responding". In Docker there's no systemctl, so `/health` alone decides. |
| Night mode | `POST /api/jarvis/sleep` with `{"asleep": true}` (and an optional `source` such as `tv`) → `POST $JARVIS_API_URL/sleep` with the caller's `Tailscale-User-Login`. The Apple TV's Night button sends it when you go to bed; Jarvis marks you up again the first time you talk to him. An older Jarvis answers 404 and the page says it can't track sleep yet. |
| Ask Jarvis (chat) | `POST $JARVIS_API_URL/chat/stream` with `{"text": ...}` and the caller's `Tailscale-User-Login`. Jarvis answers one JSON event per line (`delta`, then `done` or `error`), which the server passes straight on from `POST /api/jarvis/chat`, so the reply types out as Claude writes it. A message may carry up to 4 photos as `"images": [{"media_type": "image/jpeg", "data": "<base64>"}]` (jpeg, png, gif or webp, not HEIC; the text may then be empty), passed on to Jarvis as they are; the apps shrink photos first and the whole message may be 19 MB. History turns carry `images: n`, the count only, and Jarvis's `id` for the turn. A message may reply to one earlier message with `"replyTo": <that turn's id>` (400 when it isn't a turn id), sent on to Jarvis as `reply_to` so he knows which message is meant; the history turn then carries `replyTo: {id, role, text}` with the first 300 characters of the message replied to. A turn whose `model` starts with `notice:` (`notice:reminder`, `notice:lookout`) is a message Jarvis sent unasked; its `writer` names the model that wrote it, and its chip shows that model as usual followed by where the message came from ("Jarvis (CO) Lookout"), or plain "Jarvis" and the word when no model wrote it. When a meal photo looks like one already logged, the stream adds a `meal_question` event (`key`, `choices`: same, leftovers, new); the app answers with `POST /api/jarvis/chat/meal` `{key, choice}` → `$JARVIS_API_URL/chat/meal`, and the `message` that comes back is Jarvis's reply. `GET /api/jarvis/history` reads `$JARVIS_API_URL/chat/history?limit=50`, so a reload (or another device) shows the same conversation. Opening the chat sheet sends `POST /api/jarvis/warm` → `$JARVIS_API_URL/chat/warm`, which starts Jarvis's chat engine without asking Claude anything, so the first answer starts sooner. `POST /api/jarvis/ask` (`/ask`, one piece) is still there for other callers. Before Jarvis writes a file or runs a command on the PC he asks: an `approval` event (`id`, `tool`, `summary`, `expires`) shows Approve and Deny in the chat (in Talk the same event arrives on the voice line, and saying yes or no answers it), the page answers with `POST /api/jarvis/approve` `{id, ok}` → `$JARVIS_API_URL/approve`, and `approval_done` (`ok`, `by`: page, voice or timeout) settles the card. A tap on a request that's already over (answered out loud or on another screen, or timed out) comes back as 410 `{ok: false, gone: true, message, answer?: {ok, by, later}}`, and the card goes up into the history as it was really answered instead of coming back. `later: true` means Dylan said "wait": the card reads "Holding this for later" and Jarvis asks again when he says go ahead. Changes to Jarvis himself use the tools `change_code`, `apply_code_change` and `change_setting`, and ask in one plain sentence ("Is it OK if I change my code so…?"). `GET /api/jarvis/approvals` (`/approvals`) brings back anything still waiting after a reload. Telegram stays the backup when no page answers; after 10 minutes it counts as no. |
| Jarvis's offers | `GET $JARVIS_API_URL/offers` (in the snapshot as `offers`: `greeting` plus up to 3 `{id, title, body, start_text}`) shows his line for the moment under the Overview title, plus "Tasks I could help with" cards under the Ask bar. Hide sends `POST /api/jarvis/offers/hide` `{id}` → `$JARVIS_API_URL/offers/{id}/hide`. Start opens the chat and sends the offer's `start_text` with `offer_id` on `/chat/stream`, which counts as Dylan asking for that one step. |
| Graphics card pie | `nvidia-smi` (used, total, how busy) + Ollama `GET /api/ps` (each local model's `size_vram`) + `GET $JARVIS_API_URL/gpu` (`{models: [{name, role, mb, loaded}]}`: Jarvis's own speech and voice models, since WSL reports no per-process memory). In the snapshot as `gpu`: `{totalMb, usedMb, utilization, users: [{name, role, mb, kind}]}`, biggest first, with the unnamed remainder as "Everything else". On an older Jarvis the speech models fall into that remainder. Null when nvidia-smi fails. |
| Calories today | `GET $JARVIS_API_URL/nutrition/today` (in the snapshot as `nutrition`: `{date, eaten, goal, left, burned, protein, proteinGoal}`, numbers only, never meal names; `left` is worked out as goal minus eaten). Feeds the Apple Watch's Calories left complication. Null on an older Jarvis. |
| Meal log (the apps' Diet screen) | `GET $JARVIS_API_URL/nutrition/day?date=YYYY-MM-DD` and `/nutrition/week?start=YYYY-MM-DD`, passed through as `GET /api/jarvis/nutrition/day?date=` (`{day: {date, goals, totals, items}}`) and `/api/jarvis/nutrition/week?start=` (`{week: {start, days}}`; each day has `calories`, `goal`, `protein`, `proteinGoal`). The endless food list asks for a run of days with `GET /api/jarvis/nutrition/days?end=YYYY-MM-DD&count=7` → `$JARVIS_API_URL/nutrition/days` (`{days: [...], earliest}`: the same day objects, newest first, up to 14, and the earliest day with anything logged). A meal with `hasPhoto` has its picture at `GET /api/jarvis/nutrition/photo/<id>` (full) and `?size=thumb` (about 320 px) → `$JARVIS_API_URL/nutrition/photo/<id>`; 404 when it has none, cached privately for a day. No date means today / this week; anything that isn't a day is a 400. These carry meal names, so they're never in the snapshot and need the caller's Tailscale login. Null on an older Jarvis. |
| Notifications | `GET $JARVIS_API_URL/notices` (in the snapshot as `notices`: unread `{id, kind, title, body, source, created, approval_id?, turn_id?}`, `kind` = `need`, `heads` or `fyi`; `turn_id` is the chat history turn holding the full message, passed to the apps as `turnId` so a tap opens the chat at it) feeds the dots on the orb and the shared list in the iPhone, iPad and Apple TV apps. Clear sends `POST /api/jarvis/notices/clear` `{ids}` or `{all: true}` → `$JARVIS_API_URL/notices/clear`, so a notice cleared on one device is gone from all. Keep on a notice or on any chat message sends `POST /api/jarvis/notices/keep` `{id}` or `{turnId}` → `$JARVIS_API_URL/notices/keep` (`notice_id` / `turn_id`); a kept one carries `kept: true` (and `source: kept` when it was a chat message), shows as a yellow dot, and stays through Clear and Clear all until `POST /api/jarvis/notices/unkeep` `{id}` → `$JARVIS_API_URL/notices/unkeep` lets it go. An app sends its push token with `POST /api/jarvis/push/register` `{token, platform, environment, bundle, name?}` → `$JARVIS_API_URL/push/register`; Jarvis sends the pushes himself. Null on an older Jarvis. |
| Silent line | On the Talk line Jarvis sends `{"type": "no_audio", "seconds": N}` once when an open line has sent no sound for 20 s. The page reopens the microphone; if it can't, it hangs up saying Jarvis stopped hearing you. |
| Who answered | Jarvis sends `{"type": "model", "model": "claude" \| "ornith"}` before each reply on the chat stream and the Talk line, and `model` on `/chat/history` turns. The chat shows it as a small chip over the reply: "Jarvis (C)" in orange for Claude, "Jarvis (O)" in blue for the local model (he falls back to Ornith when Claude's plan is out of room). |
| That was wrong | Under each finished chat reply. It opens a short note ("What should he have said?", optional) and sends `POST /api/jarvis/feedback` `{question, answer, note}` → `$JARVIS_API_URL/feedback` (plus `at` and `chat: web`). Jarvis saves the flag; overnight he works out the cause, proposes one fix for an OK, and adds a regression test. On /talk, say "that's wrong" instead. |
| Playbooks | `GET $JARVIS_API_URL/playbooks` (`{playbooks: [{id, name, enabled, purpose, when_to_use, trigger, inputs, steps, decisions, done, edge_cases, standard, bad_version, made_by, last_run?: {at, ok, detail, checks: [{item, ok, why}]}}], options: {devices: [{entity, name, kind, commands}], scenes, apps: [{entity, name, apps}], zones}}`), `POST $JARVIS_API_URL/playbooks` (`{playbook}`), `POST …/playbooks/{id}/delete` and `POST …/playbooks/{id}/run` (`{ok, detail, checks}`), with the caller's `Tailscale-User-Login`; the page's side is `GET`/`POST /api/jarvis/playbooks`. An older Jarvis without them leaves the tab saying he isn't answering. |
| Reports | `GET $JARVIS_API_URL/reports` (`{reports: [{id, title, summary, created, expires, kept, keep_days, bytes}], total_bytes, keep_days, max_bytes}`; a report's own `keep_days` is 14, 30 or 90, or null when it's kept for good) is read into the snapshot; `GET …/reports/{id}` is the report's HTML, which the page serves at `/reports/<id>` with headers that stop it running scripts or loading anything from outside; `POST …/reports/{id}/keep` (`{days: 14 | 30 | 90}`, or `{keep: true}` for good, `{keep: false}` for the usual 2 weeks) and `POST …/reports/{id}/delete`, with the caller's `Tailscale-User-Login`, are the page's `POST /api/jarvis/reports`. An older Jarvis without them leaves the panel saying he isn't listing his reports. |
| How Jarvis sounds | `GET $JARVIS_API_URL/voice` (`{voice, speed, blend: {voice2, mix} \| null, voices: [{id, name, accent, gender}]}`), `POST $JARVIS_API_URL/voice` (`{voice, speed, blend}`) and `GET $JARVIS_API_URL/voice/sample?voice=&speed=&voice2=&mix=` (WAV), with the caller's `Tailscale-User-Login`; the page's side is `GET`/`POST /api/jarvis/voice` and `GET /api/jarvis/voice/sample`. |
| What Jarvis remembers | `GET $JARVIS_API_URL/memory/facts` (`{facts: [{id, text, learned, from}], turns, lastDistill}`), `GET $JARVIS_API_URL/memory/search?q=...&limit=8` (`{hits: [{chat, role, text, at}]}`) and `POST $JARVIS_API_URL/memory/facts` (`{op: "remember", text}` or `{op: "forget", id}`), all with the caller's `Tailscale-User-Login`; the page's side is `GET /api/jarvis/memory`, `GET /api/jarvis/memory/search?q=` and `POST /api/jarvis/memory`. Facts come from Jarvis's own notes file, never `memory.md`. |
| Unload / load the local model | `POST $OLLAMA_URL/api/generate` with `keep_alive: 0` (unload now) or `OLLAMA_KEEP_ALIVE` (load; `10m` by default, matching what Jarvis asks for). Ollama has no separate unload call. |
| Today (Jarvis's part) | `GET $JARVIS_API_URL/schedule/today`: Jarvis's reminders, nags and daily runs for today in Pacific time, past ones included and shown as done. An older Jarvis without it (404) just adds nothing. The Overview's Today merges these with today's calendar from the digest (`src/lib/agenda.ts`). A service that needs you isn't a row there: it's an amber banner across the top of every page (`AlertBanner`), linking to Services, with **Close** to hide it until the alerts change. |
| What Jarvis is doing | `GET $JARVIS_API_URL/jobs`: Jarvis's background jobs (Lookout, Messenger, Nightly and the quiet housekeeping) with model, schedule, last and next run and the last result, plus what Lookout is watching and held back and how many pings went out today. `running` lists the work Dylan sent to the background (`id`, `label`, `state`: running or queued, `started_at`), shown with a spinner beside the orb on /talk until it finishes. Cleaned by `server/sources/jobs.mjs` and shown on Services. An older Jarvis without it (404) shows a short note instead. |
| Fresh digest on open | `POST $JARVIS_API_URL/digest/refresh` with the caller's `Tailscale-User-Login`, sent when the page opens or comes back after 2 minutes away. Jarvis skips it if a run is going or its last write is recent. The page keeps showing the last digest, with "Updating from Jarvis…" on its panels, and checks every 5 seconds until the new one lands (giving up after 3 minutes). |

Sparkline history is kept in the server's memory (the last 24 samples, one
per snapshot), so it starts empty after a restart and fills in over a few
minutes.


## Cloud digest

On jarvis, Jarvis's `home_lab_digest` job writes the digest locally
(`DIGEST_FILE`, mounted by `docker-compose.yml`) every 15 minutes, and
again when an app asks (see "Fresh digest on open" above). The
GitHub route below is the alternative for a PC without Jarvis.

Jarvis can't see claude.ai, so its digest has no Claude threads. Claude in
the project writes them hourly into `threads.json` in the same folder
(`THREADS_FILE`, `{"updatedAt", "threads"}` in the digest's thread shape),
and the server puts them in place of the digest's empty list.

Claude project threads, today's calendar, email needing you, deploys and
open PRs can't be read from the PC: they live in claude.ai and its
connectors. A scheduled Claude task collects them every 15 minutes from 7 am to midnight
into `digest.json` in a private repo, and the server reads it with a
read-only token (cached 2 minutes, last good copy kept if GitHub is down).
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
| `PORT` | `4180` | Port for `npm start`. |
| `HA_URL` | `http://192.168.68.94:8123` | Home Assistant. |
| `HA_TOKEN` | *(empty)* | Home Assistant long-lived access token. **Secret.** Server-side only. |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Ollama's API. |
| `OLLAMA_MODEL` | `ornith-1.5:9b` | The model the local model card loads and unloads (Jarvis's local brain). Check the exact name with `ollama list`. |
| `OLLAMA_KEEP_ALIVE` | `10m` | How long Load keeps it. `-1` = forever, a number = seconds, or `30m` style. |
| `OLLAMA_WATCH_MODEL` | `ornith-1.5:9b` | Jarvis's background watch model (its `JARVIS_TRIAGE_MODEL`), so Services can say what it's doing when loaded. |
| `NVIDIA_SMI` | `/usr/lib/wsl/lib/nvidia-smi` | WSL's nvidia-smi, which isn't on PATH. |
| `JARVIS_URL` | `https://jarvis.snakebird-ph.ts.net:8443` | Jarvis's address on the tailnet, for the link on its row. |
| `JARVIS_API_URL` | `http://127.0.0.1:8765` | Jarvis's own API on the PC, for `/health` and Ask Jarvis. |
| `JARVIS_UNIT` | `jarvis` | The systemd unit to ask about (skipped in Docker, which has no systemctl). |
| `DIGEST_REPO` | `dwongbound/home-lab-digest` | Private repo holding the cloud digest. |
| `DIGEST_BRANCH` | `main` | Its branch. |
| `DIGEST_PATH` | `digest.json` | The file in it. |
| `DIGEST_TOKEN` | *(empty)* | Fine-grained GitHub token, **Contents: Read-only on that one repo**. **Secret.** Empty (and no `DIGEST_FILE`) turns the cloud panels off. |
| `SHELL_USERS` | *(empty)* | Tailscale logins allowed to use the terminal on Services, comma-separated. Empty turns the shell off. |
| `SHELL_URL` | `http://127.0.0.1:7681` | Where ttyd listens (`deploy/ttyd.service`). |
| `THREADS_FILE` | *(empty)* | Claude threads file whose `threads` replace the digest's. `docker-compose.yml` sets it to `/digest/threads.json`. |
| `MONEY_PICKS_FILE` | *(empty)* | Where Money category picks wait until you apply them in Copilot. Empty keeps them in memory (lost on restart). `docker-compose.yml` sets it to `/data/money-picks.json`, mounted read-write from `~/.local/share/home-lab/data`. |
| `DIGEST_FILE` | *(empty)* | Read the digest from this file on the PC instead of GitHub (for a digest Jarvis writes locally). No token needed. `docker-compose.yml` sets it to `/digest/digest.json`, mounted read-only from `~/.local/share/home-lab-digest/out`, where Jarvis's `home_lab_digest` job writes every 15 minutes, 7 am to midnight. |
| `SKIP_CALENDARS` | `Wong Fam` | Calendars never shown, comma-separated. Wong Fam is shared with family and holds their plans. |
| `WINDOWS_DRIVE` | `/mnt/c` | Where WSL mounts C:. |
| `HOME_LAB_ENV_FILE` | `.env` | Which env file to load. |


## Running it on jarvis

The PC runs Ubuntu 24.04 in WSL 2 with systemd on, and Ubuntu is started at
boot by the "Start Ubuntu (WSL)" task, so a systemd service is enough to
keep the server up across reboots.

```bash
# In Ubuntu on jarvis, as dwong:
git clone https://github.com/dwongbound/home-lab ~/home-lab
cd ~/home-lab
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
(which jarvis already has for Home Assistant):

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
Docker is up. **Updating:**
`git pull && docker compose up -d --build`.

The unit caps the process at 200 MB (`MemoryMax`), since the local model and
Jarvis's voice need the RAM more. It typically uses well under 100 MB.

**Updating:** `cd ~/home-lab && git pull && sudo systemctl restart home-lab`.

## Reaching it from your phone or Mac

By default the server only listens on `127.0.0.1`, which is the PC itself.
The way to open it from other devices is `tailscale serve`, the same way
Jarvis is published. It works for both the Docker and the
systemd setup, and it's what makes Ask Jarvis work, because it tells the
server (and so Jarvis) who you are. The server has the PC's main address. From Ubuntu:

```bash
TS="/mnt/c/Program Files/Tailscale/tailscale.exe"
"$TS" serve --bg --https=443 http://127.0.0.1:4180    # this server
```

Then open `https://jarvis.snakebird-ph.ts.net` on the phone or Mac with
Tailscale on.
`"$TS" serve status` lists what's published.

Two things that don't work on jarvis, so you don't have to find out:

- **Publishing on the same port the server listens on.** WSL's mirrored
  networking shares ports between Ubuntu and Windows, and `serve --http=80`
  in front of a server on `127.0.0.1:80` never answered (connection refused).
  Every service here uses two numbers (this server 4180 → 443,
  Jarvis 8765 → 8443); keep to that.
- **Plain `http://jarvis.snakebird-ph.ts.net` on port 80.** Browsers try
  `https://` first on that name, so they land on whatever is on 443. Use
  `https://`.

**Without `tailscale serve`**, for the metrics page only (the apps won't work):

1. Set `HOST=0.0.0.0` in `.env` and restart the service.
2. WSL uses **mirrored networking**, so Windows' Hyper-V firewall has to
   allow the port. In PowerShell **as Administrator** on Windows:

   ```powershell
   New-NetFirewallHyperVRule -Name "home-lab" -DisplayName "home-lab 4180" -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 4180
   ```

3. Open `http://jarvis.snakebird-ph.ts.net:4180` on the phone or Mac with
   Tailscale on.

There's no login on the server. It relies on Tailscale for who can reach it,
the same way Jarvis does. Don't expose it to the internet, and with
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
4. Open the bare URL: the services and machine bars show the real PC.
5. If a card says "Not reporting" or a service "Not responding", run the
   matching probe by hand (see [What the live source reads](#what-the-live-source-reads)),
   for example `nvidia-smi` or `curl -s http://127.0.0.1:11434/api/ps`.

## Testing

```bash
npm run typecheck     # tsc, no emit
npm test              # Vitest
```

`tests/unit/helpers.ts` `callApi` drives the handler without opening a port.

## Project layout

```
server/
  index.mjs            the server: API, /shell/ and Talk's WebSocket, node:http only
  app.mjs              the API handler, /reports/<id> and the metrics page
  metrics-page.mjs     the page at /
  config.mjs           env vars and .env loading
  sources/mock.mjs     sample data source
  sources/live.mjs     real PC source
tests/unit/            Vitest
ios/                   the Jarvis apps
deploy/                systemd units for jarvis
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

The server only reads what's listed under
[What the live source reads](#what-the-live-source-reads). It never opens
Jarvis's private memory file (`~/jarvis/data/memory.md`) or Open WebUI's
database (`/srv/open-webui/data/webui.db`), and no change should make it.
