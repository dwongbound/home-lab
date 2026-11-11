// Live source: reads the real PC.
//
// Every probe (GPU, disk, Home Assistant, Ollama, Open WebUI, Jarvis) runs
// at the same time and has a short timeout, so one slow or dead service
// never holds up the page (Vercel rule async-parallel). A probe that fails
// just shows as "Not responding" or "Not reporting".
//
// Not yet run on jarvis itself. See README, "Going live".
import os from 'node:os'
import { statfs } from 'node:fs/promises'
import { execFile as execFileCallback } from 'node:child_process'
import { promisify } from 'node:util'
import { createDigestReader } from './digest.mjs'
import { createHomeReader } from './home.mjs'
import { createPickStore } from '../money-picks.mjs'
import { createPickFile } from '../money-picks-file.mjs'

const realExecFile = promisify(execFileCallback)
const PROBE_TIMEOUT_MS = 2500
// Jarvis can take a while: Claude thinking, or Gemma loading first.
const ASK_TIMEOUT_MS = 180_000
const HISTORY_POINTS = 24
const GB = 1024 ** 3

/** Rounds to one decimal place, which is all the cards show. */
function round1(n) {
  return Math.round(n * 10) / 10
}

/**
 * Ollama wants keep_alive as a number of seconds (-1 = forever) or a
 * duration string like "30m". Env vars are always strings, so turn
 * "-1" or "3600" back into numbers and leave "30m" alone.
 */
export function parseKeepAlive(value) {
  if (/^-?\d+$/.test(value)) return Number(value)
  return value
}

/** The value of a Promise.allSettled result, or null if it failed. */
function valueOrNull(result) {
  if (result.status === 'fulfilled') return result.value
  return null
}

/**
 * Creates the live source.
 * `deps` lets tests swap in fake `fetch`, `execFile` and `statfs`.
 */
/** A Jarvis schedule kind ("reminder", "pickups"...) as a short label for the page. */
export function jarvisKindLabel(kind) {
  if (kind === 'reminder') return 'Jarvis reminder'
  if (kind === 'pickups') return 'Jarvis: fantasy pickups'
  if (kind === 'marketplace') return 'Jarvis: Marketplace scan'
  if (kind === 'nag') return 'Jarvis: nagging until done'
  return 'Jarvis'
}

export function createLiveSource(config, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch
  const execFile = deps.execFile ?? realExecFile
  const statfsFn = deps.statfs ?? statfs
  const digest = createDigestReader(config, { fetch: fetchFn })
  const home = createHomeReader(config, { fetch: fetchFn })
  // Categories picked on the Money page, kept in a file on the PC.
  const picks = deps.picks ?? createPickStore({ storage: createPickFile(config.moneyPicksFile) })

  // The sparklines need a little history. The server keeps the last 24
  // samples in memory; one sample is taken per snapshot request.
  const history = { ram: [], gpu: [], cpu: [], disk: [] }
  let previousCpuTimes = os.cpus().map((cpu) => cpu.times)

  /** Adds a sample to a sparkline's history, dropping the oldest. */
  function remember(key, value) {
    if (value === null) return
    history[key].push(round1(value))
    if (history[key].length > HISTORY_POINTS) history[key].shift()
  }

  /** CPU busy percentage since the previous call. */
  function cpuPercent() {
    const current = os.cpus().map((cpu) => cpu.times)
    let idle = 0
    let total = 0
    current.forEach((times, i) => {
      const before = previousCpuTimes[i] ?? times
      idle += times.idle - before.idle
      total += (times.user - before.user) + (times.nice - before.nice) + (times.sys - before.sys) +
        (times.irq - before.irq) + (times.idle - before.idle)
    })
    previousCpuTimes = current
    if (total === 0) return 0
    return (1 - idle / total) * 100
  }

  /** GETs a URL and reports whether it answered OK and how fast. */
  async function probeHttp(url, headers = {}) {
    const started = performance.now()
    const res = await fetchFn(url, { headers, signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    return { ok: res.ok, ms: Math.round(performance.now() - started), res }
  }

  /** GPU use from nvidia-smi, which WSL exposes for the RTX 3060. */
  async function readGpu() {
    const { stdout } = await execFile(config.nvidiaSmi, [
      '--query-gpu=memory.used,memory.total', '--format=csv,noheader,nounits',
    ], { timeout: PROBE_TIMEOUT_MS })
    const [usedMb, totalMb] = stdout.trim().split(',').map((s) => Number(s.trim()))
    return { usedGb: usedMb / 1024, totalGb: totalMb / 1024 }
  }

  /** Free and total space on the Windows C: drive, seen from WSL. */
  async function readDisk() {
    const s = await statfsFn(config.windowsDrive)
    return { freeGb: (s.bavail * s.bsize) / GB, totalGb: (s.blocks * s.bsize) / GB }
  }

  /** `systemctl is-active jarvis`: "active", "inactive", "failed"... */
  async function readUnitState() {
    try {
      const { stdout } = await execFile('systemctl', ['is-active', config.jarvisUnit], { timeout: PROBE_TIMEOUT_MS })
      return stdout.trim()
    } catch (err) {
      // systemctl exits non-zero for anything but "active" and still prints the state.
      const printed = (err.stdout ?? '').trim()
      if (printed) return printed
      return 'unknown'
    }
  }

  /** Which Ollama models are in memory right now, from /api/ps. */
  async function readLoadedModels(probe) {
    if (probe === null || !probe.ok) return []
    try {
      const body = await probe.res.json()
      return body.models ?? []
    } catch {
      return []
    }
  }

  /** Whether Ollama's expires_at is far off (keep_alive -1 shows as a date centuries away). */
  function untilOrNull(expiresAt) {
    const t = Date.parse(expiresAt ?? '')
    if (Number.isNaN(t)) return null
    // More than a year out means "stays loaded".
    if (t - Date.now() > 365 * 86400_000) return null
    return new Date(t).toISOString()
  }

  /** Ollama's /api/ps entries as the page's LoadedModel, each with its job on jarvis. */
  function describeModels(models) {
    return models.map((m) => {
      let role = 'other'
      if (m.name === config.ollamaModel) role = 'chat'
      if (m.name === config.ollamaWatchModel) role = 'watch'
      return {
        name: m.name,
        role,
        vramGb: round1((m.size_vram ?? 0) / GB),
        until: untilOrNull(m.expires_at),
        parameters: m.details?.parameter_size ?? null,
        quantization: m.details?.quantization_level ?? null,
        contextLength: typeof m.context_length === 'number' ? m.context_length : null,
      }
    })
  }

  /** For a web page (Open WebUI): any answer below 500 means the server is up. */
  function webStatus(probe) {
    if (probe !== null && probe.res.status < 500) return 'up'
    return 'down'
  }

  /** Home Assistant: OK is up, 401 means running but the token was rejected. */
  function haStatus(probe) {
    if (probe === null) return 'down'
    if (probe.ok) return 'up'
    if (probe.res.status === 401) return 'degraded'
    return 'down'
  }

  /** The words after the status for Home Assistant. */
  function haDetail(probe) {
    if (!config.haToken) return 'No token set'
    if (probe !== null && probe.res.status === 401) return 'Token rejected'
    return 'Token set'
  }

  /** Jarvis's /health answer, {"ok": true, "brain": "claude"}, or null. */
  async function readJarvisHealth(probe) {
    if (probe === null || !probe.ok) return null
    try {
      return await probe.res.json()
    } catch {
      return null
    }
  }

  /**
   * Jarvis is "up" when its /health answers. When it doesn't, it's
   * "degraded" if systemd still says active (running but stuck) and
   * "down" otherwise. In Docker there's no systemctl, so /health decides.
   */
  function jarvisStatus(unitState, health) {
    if (health !== null) return 'up'
    if (unitState === 'active') return 'degraded'
    return 'down'
  }

  /** The words after Jarvis's status: which brain it's using, or why it's quiet. */
  function jarvisDetail(unitState, health) {
    if (health !== null) return health.brain ? `Thinking with ${health.brain}` : 'Answering'
    if (unitState !== 'unknown') return `systemd says ${unitState}`
    return 'Not answering'
  }

  /** "up" with a model loaded, "idle" when Ollama runs with nothing loaded, else "down". */
  function ollamaStatus(probe, models) {
    if (probe === null || !probe.ok) return 'down'
    if (models.length > 0) return 'up'
    return 'idle'
  }

  /** "gemma4:12b and qwen3.5:9b loaded", or "No model loaded". */
  function ollamaDetail(models) {
    if (models.length === 0) return 'No model loaded'
    return `${models.map((m) => m.name).join(' and ')} loaded`
  }

  /**
   * Jarvis's reminders and jobs for today (GET /schedule/today on its local
   * API), as timeline items. Anything already past or fired is done.
   * An older Jarvis without that endpoint answers 404: no items, no error.
   */
  async function readJarvisSchedule() {
    const res = await fetchFn(`${config.jarvisApiUrl}/schedule/today`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return []
    const body = await res.json()
    const items = Array.isArray(body?.items) ? body.items : []
    const now = Date.now()
    const today = []
    for (const it of items) {
      const at = Date.parse(it?.at)
      if (Number.isNaN(at) || typeof it.text !== 'string') continue
      let status = 'scheduled'
      if (it.done === true || at < now) status = 'done'
      today.push({ id: `jarvis-${it.id ?? at}`, at: new Date(at).toISOString(), title: it.text, detail: jarvisKindLabel(it.kind), status })
    }
    return today
  }

  const haHeaders = {}
  if (config.haToken) haHeaders.Authorization = `Bearer ${config.haToken}`

  return {
    kind: 'live',

    /** One real snapshot of the PC. */
    async snapshot() {
      const results = await Promise.allSettled([
        readGpu(),
        readDisk(),
        probeHttp(`${config.haUrl}/api/`, haHeaders),
        probeHttp(`${config.ollamaUrl}/api/ps`),
        probeHttp(config.openWebUiUrl),
        probeHttp(`${config.jarvisApiUrl}/health`),
        readUnitState(),
        digest.read(),
        home.read(),
        readJarvisSchedule(),
      ])
      const [gpu, disk, ha, ollama, webui, jarvisHttp, unitResult, cloud, homeState, jarvisToday] = results.map(valueOrNull)
      const unitState = unitResult ?? 'unknown'

      const ramUsedGb = (os.totalmem() - os.freemem()) / GB
      const cpu = cpuPercent()
      remember('ram', ramUsedGb)
      remember('cpu', cpu)
      remember('gpu', gpu === null ? null : gpu.usedGb)
      remember('disk', disk === null ? null : disk.freeGb)

      const models = await readLoadedModels(ollama)
      const jarvisHealth = await readJarvisHealth(jarvisHttp)
      // The Gemma card is only ever about Gemma; anything else loaded (like
      // Jarvis's watch model) is listed on its own.
      const model = models.find((m) => m.name === config.ollamaModel)

      return {
        generatedAt: new Date().toISOString(),
        source: 'live',
        host: { name: os.hostname(), os: `${os.type()} ${os.release()}`, uptimeSec: Math.round(os.uptime()) },
        metrics: [
          { id: 'ram', label: 'Memory', value: round1(ramUsedGb), unit: 'GB', total: round1(os.totalmem() / GB), history: [...history.ram] },
          { id: 'gpu', label: 'GPU memory', value: gpu && round1(gpu.usedGb), unit: 'GB', total: gpu && round1(gpu.totalGb), history: [...history.gpu] },
          { id: 'cpu', label: 'Processor', value: Math.round(cpu), unit: '%', total: 100, history: [...history.cpu] },
          { id: 'disk', label: 'Free on C:', value: disk && Math.round(disk.freeGb), unit: 'GB', total: disk && Math.round(disk.totalGb), history: [...history.disk] },
        ],
        // Jarvis doesn't publish request counts or an activity log yet.
        // Empty lists make the page show its empty states.
        requests: [],
        today: jarvisToday ?? [],
        activity: [],
        services: [
          { id: 'ha', name: 'Home Assistant', detail: haDetail(ha), status: haStatus(ha), latencyMs: ha?.ms, url: config.haUrl },
          { id: 'ollama', name: 'Ollama', detail: ollamaDetail(models), status: ollamaStatus(ollama, models), latencyMs: ollama?.ms },
          { id: 'webui', name: 'Open WebUI', detail: 'Chat with Gemma', status: webStatus(webui), latencyMs: webui?.ms, url: config.openWebUiUrl },
          { id: 'jarvis', name: 'Jarvis', detail: jarvisDetail(unitState, jarvisHealth), status: jarvisStatus(unitState, jarvisHealth), latencyMs: jarvisHttp?.ms, url: config.jarvisUrl },
        ],
        model: {
          name: config.ollamaModel,
          loaded: Boolean(model),
          vramGb: model ? round1((model.size_vram ?? 0) / GB) : 0,
          loadSeconds: null,
        },
        models: describeModels(models),
        cloud,
        home: homeState,
        moneyPicks: await picks.read(cloud?.money?.recent ?? []),
      }
    },

    /** Saves, clears or re-times categories picked on the Money page (server/money-picks.mjs). */
    async money(change) {
      return picks.change(change)
    },

    /**
     * Loads or unloads Gemma. Ollama has no "unload" call: you send an empty
     * generate request with keep_alive 0 (unload now) or OLLAMA_KEEP_ALIVE
     * (load and keep it that long; -1 = forever, how jarvis runs it).
     */
    async action(name) {
      if (name !== 'ollama-unload' && name !== 'ollama-load') {
        return { ok: false, message: `Unknown action: ${name}` }
      }
      const unloading = name === 'ollama-unload'
      const res = await fetchFn(`${config.ollamaUrl}/api/generate`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model: config.ollamaModel, keep_alive: unloading ? 0 : parseKeepAlive(config.ollamaKeepAlive) }),
        // Loading Gemma takes about 3 minutes on this PC, so allow 5.
        signal: AbortSignal.timeout(unloading ? 30_000 : 300_000),
      })
      if (!res.ok) return { ok: false, message: `Ollama answered ${res.status}` }
      return { ok: true, message: unloading ? 'Gemma unloaded' : 'Gemma loaded' }
    },

    /**
     * Controls one Home Assistant device. Like Ask Jarvis, it needs the
     * Tailscale login that `tailscale serve` adds, so only someone on the
     * tailnet (not anything else on the PC or the home network) can do it.
     */
    async control(entityId, command, value, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to control the house' }
      const now = await home.read()
      const current = now?.devices.find((d) => d.id === entityId)?.state
      return home.act(entityId, command, value, current)
    },

    /**
     * Asks Jarvis through its /ask endpoint, the same one the Siri Shortcut
     * uses. `caller.login` is the Tailscale login of whoever opened the
     * page; Jarvis refuses anyone not on its own list.
     */
    async ask(text, caller = {}) {
      if (!caller.login) {
        return { ok: false, message: 'Open this page through Tailscale to talk to Jarvis' }
      }
      let res
      try {
        res = await fetchFn(`${config.jarvisApiUrl}/ask`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify({ text }),
          signal: AbortSignal.timeout(ASK_TIMEOUT_MS),
        })
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
      if (res.status === 401) return { ok: false, message: `Jarvis doesn't know ${caller.login}` }
      if (!res.ok) return { ok: false, message: `Jarvis answered ${res.status}` }
      const body = await res.json().catch(() => ({}))
      return { ok: true, message: String(body.reply ?? '') }
    },

    /**
     * Asks Jarvis to rewrite the digest now (POST /digest/refresh). Jarvis
     * skips it when a run is going or the last write is under 2 minutes
     * old, and answers at once; the page keeps showing the last digest
     * meanwhile. Anything but a clear answer counts as "not running".
     */
    async refreshDigest(caller = {}) {
      const idle = { running: false, lastWrite: null }
      if (!caller.login) return idle
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/digest/refresh`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return idle
        const body = await res.json()
        let lastWrite = null
        if (typeof body?.lastWrite === 'string') lastWrite = body.lastWrite
        return { running: body?.running === true, lastWrite }
      } catch {
        return idle
      }
    },
  }
}
