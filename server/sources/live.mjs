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

const realExecFile = promisify(execFileCallback)
const PROBE_TIMEOUT_MS = 2500
const HISTORY_POINTS = 24
const GB = 1024 ** 3

/** Rounds to one decimal place, which is all the cards show. */
function round1(n) {
  return Math.round(n * 10) / 10
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
export function createLiveSource(config, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch
  const execFile = deps.execFile ?? realExecFile
  const statfsFn = deps.statfs ?? statfs

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
    const { stdout } = await execFile('nvidia-smi', [
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

  /** "up" if the probe answered OK, otherwise "down". */
  function httpStatus(probe) {
    if (probe !== null && probe.ok) return 'up'
    return 'down'
  }

  /**
   * Jarvis is "up" when systemd says active AND its web port answers,
   * "degraded" when systemd says active but the port doesn't answer,
   * and "down" otherwise.
   */
  function jarvisStatus(unitState, probe) {
    if (unitState !== 'active') return 'down'
    if (probe !== null && probe.ok) return 'up'
    return 'degraded'
  }

  /** "up" with a model loaded, "idle" when Ollama runs with nothing loaded, else "down". */
  function ollamaStatus(probe, model) {
    if (probe === null || !probe.ok) return 'down'
    if (model) return 'up'
    return 'idle'
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
        probeHttp(config.jarvisUrl),
        readUnitState(),
      ])
      const [gpu, disk, ha, ollama, webui, jarvisHttp, unitResult] = results.map(valueOrNull)
      const unitState = unitResult ?? 'unknown'

      const ramUsedGb = (os.totalmem() - os.freemem()) / GB
      const cpu = cpuPercent()
      remember('ram', ramUsedGb)
      remember('cpu', cpu)
      remember('gpu', gpu === null ? null : gpu.usedGb)
      remember('disk', disk === null ? null : disk.freeGb)

      const models = await readLoadedModels(ollama)
      const model = models.find((m) => m.name === config.ollamaModel) ?? models[0]

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
        // Jarvis doesn't publish request counts, its schedule or an activity
        // log yet. Empty lists make the page show its empty states.
        requests: [],
        today: [],
        activity: [],
        services: [
          { id: 'ha', name: 'Home Assistant', detail: config.haToken ? 'Token set' : 'No token set', status: httpStatus(ha), latencyMs: ha?.ms, url: config.haUrl },
          { id: 'ollama', name: 'Ollama', detail: model ? `${model.name} loaded` : 'No model loaded', status: ollamaStatus(ollama, model), latencyMs: ollama?.ms },
          { id: 'webui', name: 'Open WebUI', detail: 'Chat with Gemma', status: httpStatus(webui), latencyMs: webui?.ms, url: config.openWebUiUrl },
          { id: 'jarvis', name: 'Jarvis', detail: `systemd says ${unitState}`, status: jarvisStatus(unitState, jarvisHttp), latencyMs: jarvisHttp?.ms, url: config.jarvisUrl },
        ],
        model: {
          name: model?.name ?? config.ollamaModel,
          loaded: Boolean(model),
          vramGb: model ? round1((model.size_vram ?? 0) / GB) : 0,
          loadSeconds: null,
        },
      }
    },

    /**
     * Loads or unloads Gemma. Ollama has no "unload" call: you send an empty
     * generate request with keep_alive 0 (unload now) or a duration (load
     * and keep it for that long).
     */
    async action(name) {
      if (name !== 'ollama-unload' && name !== 'ollama-load') {
        return { ok: false, message: `Unknown action: ${name}` }
      }
      const unloading = name === 'ollama-unload'
      const res = await fetchFn(`${config.ollamaUrl}/api/generate`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model: config.ollamaModel, keep_alive: unloading ? 0 : '30m' }),
        // Loading Gemma takes about 3 minutes on this PC, so allow 5.
        signal: AbortSignal.timeout(unloading ? 30_000 : 300_000),
      })
      if (!res.ok) return { ok: false, message: `Ollama answered ${res.status}` }
      return { ok: true, message: unloading ? 'Gemma unloaded' : 'Gemma loaded' }
    },
  }
}
