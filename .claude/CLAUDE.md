# home-lab — conventions for Claude

## Workflow

- Every change lands as a PR against **`dev`**. Never commit to `main` directly.
- CI merges a PR into `dev` by itself once tests pass (rebase, branch deleted),
  then fast-forwards `main` to `dev` (Dylan, 2026-11-09: no clicks to reach main).
  Open a PR as a **draft** to hold it; mark it ready when it should merge.
- Tests with every change, passing before merge, on any machine (not just CI).
- **The React web page is gone (Dylan, 2026-11-26).** The native apps in `ios/` are the product. The server and its `/api`, `/reports/<id>`, `/shell/` and the Talk WebSocket stay and keep growing, because the apps reach Jarvis through them. `/` is one plain server-rendered metrics page (`server/metrics-page.mjs`): no scripts, no framework, keep it that way.
- A config change updates `.env.example` and the README in the same PR.
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

## Secrets and privacy

- The HA token stays server-side (`server/config.mjs`); a unit test checks no
  response contains it. Never echo it.
- Never open `~/jarvis/data/memory.md` or `/srv/open-webui/data/webui.db`.
