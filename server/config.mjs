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
    ollamaModel: env.OLLAMA_MODEL ?? 'gemma4:12b',
    // How long Ollama keeps Gemma after Load. "-1" = forever, which is how
    // jarvis normally runs it. A number is seconds; "30m" style also works.
    ollamaKeepAlive: env.OLLAMA_KEEP_ALIVE ?? '-1',
    openWebUiUrl: env.OPEN_WEBUI_URL ?? 'https://jarvis.snakebird-ph.ts.net',
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
    // Where WSL mounts the Windows C: drive.
    windowsDrive: env.WINDOWS_DRIVE ?? '/mnt/c',
  }
}
