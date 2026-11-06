# home-lab — conventions for Claude

## Workflow

- Every change lands as a PR against **`dev`**. `dev` → `main` is Dylan's.
- Tests with every change, passing before merge, on any machine (not just CI).
  Unit tests for small pieces; Playwright end-to-end for user stories on
  **desktop and phone**.
- A config change updates `.env.example` and the README in the same PR.
- UI changes start as a clickable mockup (the `build:preview` page works for this).
- **Commit messages:** a succinct one-line subject, blank line, then one bullet
  per change naming the key files or areas. No prose paragraphs.

## Readability (same rules as TapWorship)

- Every function and component gets a comment saying what it does. Confusing
  lines and workarounds get a comment saying why.
- Human readable over clever: plain `if`s instead of nested ternaries,
  small named helpers, even some duplication if it reads better.
- No dead code: nothing declared that isn't used (`noUnusedLocals` is on).
- One request per refresh: if two things are always fetched together they
  belong in the one snapshot.

## UI rules

- Dismiss buttons read **Close**.
- Anything waiting on the network shows a blocking indicator with a label.
- Motion degrades to the plain page; animations only inside the
  no-preference media block. Glass falls back to solid without backdrop-filter.
- Logs newest first. Fixed-size dialogs. 44 px touch targets on phones.
- Keep the page light: jarvis has 16 GB and Gemma uses most of it. No UI
  framework, chart or icon library without a good reason.

## Secrets and privacy

- The HA token stays server-side (`server/config.mjs`); a unit test checks no
  response contains it. Never echo it.
- Never open `~/jarvis/data/memory.md` or `/srv/open-webui/data/webui.db`.
