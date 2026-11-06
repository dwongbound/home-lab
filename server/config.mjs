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
    ollamaModel: env.OLLAMA_MODEL ?? 'gemma3:12b',
    openWebUiUrl: env.OPEN_WEBUI_URL ?? 'https://jarvis.snakebird-ph.ts.net',
    jarvisUrl: env.JARVIS_URL ?? 'https://jarvis.snakebird-ph.ts.net:8443',
    jarvisUnit: env.JARVIS_UNIT ?? 'jarvis',
    // Where WSL mounts the Windows C: drive.
    windowsDrive: env.WINDOWS_DRIVE ?? '/mnt/c',
  }
}
