# The cloud digest

The PC can't see claude.ai or Dylan's claude.ai connectors (Calendar, Gmail,
GitHub, Vercel, Neon). A scheduled Claude task in the **Home AI Lab** project
can, so once an hour from 7 am to 11 pm Pacific it collects them into one
file and commits it to a **private** repo. The page's server reads that file
with a read-only token (`server/sources/digest.mjs`) and shows it on the
Claude, Overview and Schedule pages.

```
 claude.ai project ── scheduled task (hourly) ──▶ private repo: digest.json
                                                        │  read-only token,
                                                        ▼  cached 5 min
                                             jarvis: home-lab server ──▶ page
```

Each run shows up as its own thread in the project and resolves itself.

## Why a separate private repo

`home-lab` is public. The digest holds email subjects, calendar events and
thread titles, so it lives in its own private repo, `home-lab-digest`, and
the token on the PC can read only that repo.

## Setting it up

1. Create an empty **private** repo `dwongbound/home-lab-digest` and add it to
   the Home AI Lab project.
2. Make a fine-grained token at GitHub → Settings → Developer settings →
   Fine-grained tokens: repository access **only `home-lab-digest`**,
   permission **Contents: Read-only**, expiry a year.
3. On jarvis, put it in `~/home-lab/.env` as `DIGEST_TOKEN=` and restart the page.

## The file

`digest.json`, matching `CloudDigest` in `src/types.ts`:

```json
{
  "updatedAt": "2026-11-06T17:48:00Z",
  "threads": [
    { "id": "cmsg_…", "title": "Build glassy home lab admin page", "state": "working",
      "lastActivityAt": "2026-11-06T17:46:00Z",
      "url": "https://claude.ai/code/project/chan_…?thread=cmsg_…" }
  ],
  "calendar": [
    { "id": "…", "title": "Worship practice", "start": "2026-11-07T03:30:00Z",
      "end": "2026-11-07T05:00:00Z", "allDay": false, "calendar": "Church" }
  ],
  "email": [ { "id": "…", "from": "Google Cloud", "subject": "…", "why": "Waiting on your scope declaration" } ],
  "deploys": [ { "project": "tapworship.com", "state": "ready", "at": "…", "url": "https://tapworship.com" } ],
  "pullRequests": [ { "repo": "home-lab", "number": 2, "title": "…", "ci": "passing", "url": "…" } ]
}
```

- `threads[].state` is one of `working`, `blocked` (waiting on Dylan),
  `review_ready`, `done`, `failed`, `stopped`. Threads active in the last 7 days only.
- `calendar` is today in Pacific time, across all of his calendars.
- `email` is at most three messages that need him, with a few words on why.
  Never message bodies.
- `deploys` are the latest production deploys of tapworship.com and vardafreeflyers.com.
- `pullRequests` are his open PRs on worship-scheduler, vff-app and home-lab.

## The scheduled task's prompt

Kept here so it's reviewed like code. If it changes, update the task too.

> Build the home-lab digest. Write one JSON file matching
> `docs/digest.md` in dwongbound/home-lab and commit it as `digest.json` on
> `main` of the private repo dwongbound/home-lab-digest, replacing the old
> one, with the commit message "Digest <ISO time>". Use `list_threads`
> (threads active in the last 7 days, skipping threads titled
> "home-lab digest"), Google Calendar (`list_calendars`, then today's events
> on every calendar, in Pacific time), Gmail (at most three threads from the
> last 2 days that need Dylan's reply or action; subject, sender and a few
> words on why, never bodies), Vercel (latest production deploy of
> tapworship.com and vardafreeflyers.com), and GitHub (Dylan's open PRs on
> dwongbound/worship-scheduler, vff-app and home-lab, with CI state). If a
> source fails, leave its list empty and carry on. Don't post, message, email
> or change anything else. When the commit is pushed, resolve this thread.
