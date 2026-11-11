// Everything the server reads from the environment, with the defaults for
// jarvis. Secrets (the Home Assistant token) are read here and never leave
// the server: no endpoint returns them and the page never sees them.

/**
 * Loads variables from a .env file into process.env, if the file exists.
 * Variables already set in the environment win over the file.
 * Uses Node's built-in loader (Node 20.12 and later), so no dotenv package.
 */
export function loadEnvFile(path = process.env.HOME_LAB_ENV_FILE ?? '.env') {
  try {
    process.loadEnvFile(path)
  } catch (err) {
    // A missing file is normal (mock mode needs nothing). Anything else is real.
    if (err?.code !== 'ENOENT') throw err
  }
}

/** Reads the server's settings from `env` (process.env by default). */
export function loadConfig(env = process.env) {
  return {
    port: Number(env.PORT ?? 4180),
    // Localhost by default. Set HOST=0.0.0.0 to reach it over Tailscale.
    host: env.HOST ?? '127.0.0.1',
    dataSource: env.DATA_SOURCE === 'live' ? 'live' : 'mock',
    haUrl: env.HA_URL ?? 'http://192.168.68.94:8123',
    haToken: env.HA_TOKEN ?? '',
    ollamaUrl: env.OLLAMA_URL ?? 'http://127.0.0.1:11434',
    // Jarvis's local model (Gemma was dropped 2026-11-11): its offline
    // backup brain and background watch. The model card loads and unloads it.
    ollamaModel: env.OLLAMA_MODEL ?? 'ornith-1.5:9b',
    // How long Ollama keeps it after Load, like Jarvis's own requests (10
    // minutes idle). "-1" = forever; a number is seconds; "30m" style works.
    ollamaKeepAlive: env.OLLAMA_KEEP_ALIVE ?? '10m',
    // Jarvis's background watch model (JARVIS_TRIAGE_MODEL in Jarvis), so
    // the Services page can say what it's doing when it's loaded.
    ollamaWatchModel: env.OLLAMA_WATCH_MODEL ?? 'ornith-1.5:9b',
    jarvisUrl: env.JARVIS_URL ?? 'https://jarvis.snakebird-ph.ts.net:8443',
    jarvisUnit: env.JARVIS_UNIT ?? 'jarvis',
    // Jarvis's own HTTP API (/health, /ask), which listens on this PC only.
    jarvisApiUrl: env.JARVIS_API_URL ?? 'http://127.0.0.1:8765',
    // WSL puts nvidia-smi here, and it isn't on PATH by default.
    nvidiaSmi: env.NVIDIA_SMI ?? '/usr/lib/wsl/lib/nvidia-smi',
    // The cloud digest (docs/digest.md): a private repo, a read-only token
    // that can see only that repo, and where the file sits in it.
    digestRepo: env.DIGEST_REPO ?? 'dwongbound/home-lab-digest',
    digestBranch: env.DIGEST_BRANCH ?? 'main',
    digestPath: env.DIGEST_PATH ?? 'digest.json',
    digestToken: env.DIGEST_TOKEN ?? '',
    // Or a digest file on this PC (written by Jarvis); no token needed.
    digestFile: env.DIGEST_FILE ?? '',
    // Dylan's Claude threads, written onto this PC hourly by Claude in his
    // project; they replace the digest's (empty) threads.
    threadsFile: env.THREADS_FILE ?? '',
    // Where the Money page keeps categories Dylan picked for purchases
    // Copilot left unsorted, until he applies them in Copilot. Empty keeps
    // them in memory (gone on restart).
    moneyPicksFile: env.MONEY_PICKS_FILE ?? '',
    // Calendars never shown, comma-separated. "Wong Fam" is shared with
    // Dylan's parents and holds their plans.
    skipCalendars: (env.SKIP_CALENDARS ?? 'Wong Fam').split(',').map((s) => s.trim()).filter(Boolean),
    // The Shell page: ttyd on this PC (deploy/ttyd.service), and the
    // Tailscale logins allowed to use it. Empty turns the shell off.
    shellUrl: env.SHELL_URL ?? 'http://127.0.0.1:7681',
    shellUsers: (env.SHELL_USERS ?? '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
    // Where WSL mounts the Windows C: drive.
    windowsDrive: env.WINDOWS_DRIVE ?? '/mnt/c',
  }
}
