// Live source: reads the real PC.
//
// Every probe (GPU, disk, Home Assistant, Ollama, Jarvis) runs
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
import { buildGpu, ollamaRows, parseJarvisGpu, parseSmi } from './gpu.mjs'
import { HISTORY_DEFAULT, emptyHistory, historyQuery, parseHistory } from './history.mjs'
import { parseJobs } from './jobs.mjs'
import { parseOffers } from './offers.mjs'
import { parseNotice, parseNotices } from './notices.mjs'
import { parseNutrition, parseNutritionDay, parseNutritionDays, parseNutritionWeek, photoType } from './nutrition.mjs'
import { fromJarvisDraft, parseChecks, parsePlaybookBook, toJarvisPlaybook } from './playbooks.mjs'
import { parseReport, parseReports } from './reports.mjs'
import { createPickStore } from '../money-picks.mjs'
import { createPickFile } from '../money-picks-file.mjs'

const realExecFile = promisify(execFileCallback)
// Making a voice sample can take a few seconds when the GPU is busy.
const SAMPLE_TIMEOUT_MS = 15_000
const PROBE_TIMEOUT_MS = 2500
// Running a playbook by hand waits for its steps (a TV waking, a pause between
// steps, Jarvis thinking one through) and for him to check his done list.
const PLAYBOOK_RUN_TIMEOUT_MS = 180_000
// Drafting a playbook is one model call on Jarvis's side.
const PLAYBOOK_DRAFT_TIMEOUT_MS = 45000
// Jarvis can take a while: Claude thinking, or the local model loading first.
const ASK_TIMEOUT_MS = 180_000
// A chat reply can wait on an approval for up to 10 minutes, so its stream gets longer.
const CHAT_TIMEOUT_MS = 13 * 60_000

/** One approval request from Jarvis, checked and trimmed; null if it's missing a field. */
function toApproval(raw) {
  if (typeof raw?.id !== 'string' || typeof raw.summary !== 'string') return null
  return {
    id: raw.id.slice(0, 64),
    tool: String(raw.tool ?? '').slice(0, 60),
    summary: raw.summary.slice(0, 4000),
    expires: typeof raw.expires === 'string' ? raw.expires : '',
  }
}

/**
 * What to tell the page when Approve or Deny was tapped on a request that's
 * already over (Jarvis answers 404 with why, and how it was answered when
 * he still remembers). `gone` tells every screen to drop the card for good
 * (Dylan, 2026-11-18: a card answered by voice kept coming back).
 */
function goneApproval(body) {
  const said = typeof body?.error === 'string' && body.error ? body.error : 'that request was already answered or ran out of time'
  const result = { ok: false, gone: true, message: said.charAt(0).toUpperCase() + said.slice(1) }
  if (typeof body?.answer?.ok === 'boolean') {
    result.answer = { ok: body.answer.ok, by: toApprovalBy(body.answer.by), later: body.answer.later === true }
  }
  return result
}

/** Who answered an approval, as one of the three the page knows. */
function toApprovalBy(by) {
  if (by === 'page' || by === 'voice') return by
  return 'timeout'
}
// A report can be up to 1 MB, so it gets longer than a probe.
const REPORT_TIMEOUT_MS = 10_000
// Stopping a job waits for its processes to end and its leftovers to be cleared.
const STOP_TIMEOUT_MS = 30_000

/** A short line Jarvis said, or null when he said nothing usable. */
function saidText(value) {
  if (typeof value !== 'string' || value.trim() === '') return null
  return value.trim().slice(0, 200)
}
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
/** The status codes Jarvis's address gives while he is down or coming back up after a restart. */
const RESTARTING = [502, 503, 504]

/** How long the chat waits before its one retry when Jarvis is restarting. */
const RESTART_WAIT_MS = 2500

/** What to tell the page when Jarvis answers with an error code: plain words while he restarts, the code otherwise. */
export function jarvisSaid(status) {
  if (RESTARTING.includes(status)) return 'Jarvis is restarting. Try again in a moment.'
  return `Jarvis answered ${status}`
}

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
  // Tests pass 0 so the chat's retry across a restart doesn't hold them up.
  const restartWaitMs = deps.restartWaitMs ?? RESTART_WAIT_MS
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
      '--query-gpu=memory.used,memory.total,utilization.gpu', '--format=csv,noheader,nounits',
    ], { timeout: PROBE_TIMEOUT_MS })
    const smi = parseSmi(stdout)
    if (smi === null) throw new Error('nvidia-smi gave no numbers')
    return { ...smi, usedGb: smi.usedMb / 1024, totalGb: smi.totalMb / 1024 }
  }

  /** Jarvis's own models on the card (GET /gpu); none on an older Jarvis or when he's down. */
  async function readJarvisGpu() {
    const res = await fetchFn(`${config.jarvisApiUrl}/gpu`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return []
    return parseJarvisGpu(await res.json())
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

  /** The words after Jarvis's status: which brain it's using (and which build, when he says), or why it's quiet. */
  function jarvisDetail(unitState, health) {
    if (health !== null) {
      const brain = health.brain ? `Thinking with ${health.brain}` : 'Answering'
      const version = jarvisVersion(health.version)
      return version ? `${brain} · ${version}` : brain
    }
    if (unitState !== 'unknown') return `systemd says ${unitState}`
    return 'Not answering'
  }

  /**
   * "build 142" from /health's version, so Dylan can compare the running
   * Jarvis with a pending build (2026-11-16: build numbers only, no hashes);
   * "with unsaved edits" when the tree has uncommitted changes, "pending
   * build 143" when the next build is staged for his OK.
   */
  function jarvisVersion(version) {
    if (!version || typeof version !== 'object' || !Number.isInteger(version.build)) return ''
    let text = `build ${version.build}`
    if (version.dirty === true) text += ' with unsaved edits'
    if (version.pending && typeof version.pending === 'object') {
      // Jarvis names the staged build's number; older shapes only imply the next one.
      const next = Number.isInteger(version.pending.build) ? version.pending.build : version.build + 1
      text += `, pending build ${next}`
    }
    return text
  }

  /** "up" with a model loaded, "idle" when Ollama runs with nothing loaded, else "down". */
  function ollamaStatus(probe, models) {
    if (probe === null || !probe.ok) return 'down'
    if (models.length > 0) return 'up'
    return 'idle'
  }

  /** "ornith-1.5:9b loaded" (several joined with "and"), or "No model loaded". */
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

  /**
   * What Jarvis is doing in the background (GET /jobs). Null when an older
   * Jarvis answers 404 or the answer isn't the expected shape.
   */
  async function readJarvisJobs() {
    const res = await fetchFn(`${config.jarvisApiUrl}/jobs`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return null
    return parseJobs(await res.json())
  }

  /** The reports Jarvis has written (GET /reports); null when an older Jarvis answers 404. */
  async function readJarvisReports() {
    const res = await fetchFn(`${config.jarvisApiUrl}/reports`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return null
    return parseReports(await res.json())
  }

  /** Jarvis's greeting and offers (GET /offers); null when an older Jarvis answers 404. */
  async function readJarvisOffers() {
    const res = await fetchFn(`${config.jarvisApiUrl}/offers`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return null
    return parseOffers(await res.json())
  }

  /** Jarvis's unread notifications (GET /notices); null when an older Jarvis answers 404. */
  async function readJarvisNotices() {
    const res = await fetchFn(`${config.jarvisApiUrl}/notices`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return null
    return parseNotices(await res.json())
  }

  /** Today's calories eaten and goal (GET /nutrition/today); null when an older Jarvis answers 404. */
  async function readJarvisNutrition() {
    const res = await fetchFn(`${config.jarvisApiUrl}/nutrition/today`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    if (!res.ok) return null
    return parseNutrition(await res.json())
  }

  /** POSTs JSON to Jarvis as the caller; `done` is what to say when it works, `missing` when an older Jarvis answers 404. */
  async function postToJarvis(path, body, caller, done, missing) {
    if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to tell Jarvis' }
    try {
      const res = await fetchFn(`${config.jarvisApiUrl}${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
      })
      if (res.status === 404) return { ok: false, message: missing }
      if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
      return { ok: true, message: done }
    } catch {
      return { ok: false, message: 'Jarvis is not answering' }
    }
  }

  /** What to say after a report's keep time changed: "Keeping it 1 month". */
  function keepMessage(change) {
    if (change.days === 30) return 'Keeping it 1 month'
    if (change.days === 90) return 'Keeping it 3 months'
    if (change.keep === true) return 'Keeping it until you change that'
    return 'Keeping it 2 weeks'
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
        probeHttp(`${config.jarvisApiUrl}/health`),
        readUnitState(),
        digest.read(),
        home.read(),
        readJarvisSchedule(),
        readJarvisJobs(),
        readJarvisOffers(),
        readJarvisNotices(),
        readJarvisNutrition(),
        readJarvisReports(),
        readJarvisGpu(),
      ])
      const [gpu, disk, ha, ollama, jarvisHttp, unitResult, cloud, homeState, jarvisToday, jobs, offers, notices, nutrition, reports, speechModels] = results.map(valueOrNull)
      const unitState = unitResult ?? 'unknown'

      const ramUsedGb = (os.totalmem() - os.freemem()) / GB
      const cpu = cpuPercent()
      remember('ram', ramUsedGb)
      remember('cpu', cpu)
      remember('gpu', gpu === null ? null : gpu.usedGb)
      remember('disk', disk === null ? null : disk.freeGb)

      const models = await readLoadedModels(ollama)
      const jarvisHealth = await readJarvisHealth(jarvisHttp)
      // The model card is only ever about OLLAMA_MODEL; anything else
      // loaded is listed on its own.
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
          { id: 'jarvis', name: 'Jarvis', detail: jarvisDetail(unitState, jarvisHealth), status: jarvisStatus(unitState, jarvisHealth), latencyMs: jarvisHttp?.ms, url: config.jarvisUrl },
        ],
        model: {
          name: config.ollamaModel,
          loaded: Boolean(model),
          vramGb: model ? round1((model.size_vram ?? 0) / GB) : 0,
          loadSeconds: null,
        },
        models: describeModels(models),
        gpu: buildGpu(gpu, [...ollamaRows(models, config.ollamaWatchModel), ...(speechModels ?? [])]),
        cloud,
        home: homeState,
        jobs,
        moneyPicks: await picks.read(cloud?.money?.recent ?? []),
        offers,
        notices,
        nutrition,
        reports,
      }
    },

    /** Saves, clears or re-times categories picked on the Money page (server/money-picks.mjs). */
    async money(change) {
      return picks.change(change)
    },

    /**
     * Loads or unloads the local model. Ollama has no "unload" call: you
     * send an empty generate request with keep_alive 0 (unload now) or
     * OLLAMA_KEEP_ALIVE (load and keep it that long; 10m by default).
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
        // A cold load can take a few minutes on this PC, so allow 5.
        signal: AbortSignal.timeout(unloading ? 30_000 : 300_000),
      })
      if (!res.ok) return { ok: false, message: `Ollama answered ${res.status}` }
      return { ok: true, message: unloading ? 'Local model unloaded' : 'Local model loaded' }
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
      if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
      const body = await res.json().catch(() => ({}))
      return { ok: true, message: String(body.reply ?? '') }
    },

    /**
     * Talks to Jarvis's streaming chat (POST /chat/stream, chat "web") and
     * hands each event on as it arrives: {type: 'delta', text}, then
     * {type: 'done', ok: true} or {type: 'error', message}. Jarvis sends one
     * JSON object per line.
     */
    async chat(text, caller, onEvent) {
      if (!caller.login) {
        onEvent({ type: 'error', message: 'Open this page through Tailscale to talk to Jarvis' })
        return
      }
      const message = { text }
      if (caller.offerId) message.offer_id = caller.offerId
      // Photos go along as base64, the way Claude takes them.
      if (caller.images) message.images = caller.images.map((image) => ({ media_type: image.type, data: image.data }))
      /** Sends the message to Jarvis; null when he can't be reached at all. */
      const send = async () => {
        try {
          return await fetchFn(`${config.jarvisApiUrl}/chat/stream`, {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
            body: JSON.stringify(message),
            signal: AbortSignal.timeout(CHAT_TIMEOUT_MS),
          })
        } catch {
          return null
        }
      }
      let res = await send()
      // He restarts for a few seconds after each change to himself. The message
      // never reached him, so it's safe to wait a moment and send it once more.
      if (!res || RESTARTING.includes(res.status)) {
        await new Promise((resolve) => setTimeout(resolve, restartWaitMs))
        res = await send()
      }
      if (!res) {
        onEvent({ type: 'error', message: 'Jarvis is not answering' })
        return
      }
      if (res.status === 401) return onEvent({ type: 'error', message: `Jarvis doesn't know ${caller.login}` })
      if (!res.ok || !res.body) return onEvent({ type: 'error', message: jarvisSaid(res.status) })
      let ended = false
      try {
        for await (const event of readJsonLines(res.body)) {
          if (event.type === 'delta' && typeof event.text === 'string') onEvent({ type: 'delta', text: event.text })
          else if (event.type === 'done') { ended = true; onEvent({ type: 'done', ok: true }) }
          else if (event.type === 'error') { ended = true; onEvent({ type: 'error', message: String(event.message ?? 'Jarvis hit an error') }) }
          else if (event.type === 'approval') {
            const approval = toApproval(event)
            if (approval) onEvent({ type: 'approval', approval })
          } else if (event.type === 'approval_done' && typeof event.id === 'string') {
            onEvent({ type: 'approval_done', id: event.id, ok: event.ok === true, by: toApprovalBy(event.by), later: event.later === true })
          } else if (event.type === 'meal_question' && typeof event.key === 'string' && Array.isArray(event.choices)) {
            // A meal photo that looks like one already logged: the app shows the choices as buttons.
            onEvent({ type: 'meal_question', key: event.key, choices: event.choices.filter((c) => typeof c === 'string') })
          } else if (event.type === 'model' && typeof event.model === 'string') {
            // Who is answering: Claude, or the local model while Claude's plan is out of room.
            onEvent({ type: 'model', model: event.model })
          } else if (event.type === 'turn' && Number.isInteger(event.id) && event.id > 0) {
            // His number for the message just sent, so the apps can find its reply in the history later.
            onEvent({ type: 'turn', id: event.id })
          }
        }
      } catch {
        // The connection dropped mid-reply; say so below.
      }
      if (!ended) onEvent({ type: 'error', message: 'Jarvis stopped answering partway' })
    },

    /**
     * Tells Jarvis the one who asked has closed the app before the reply was
     * done (POST /chat/left), so he pushes the reply to the phone when it's
     * ready. turnId is null when Jarvis hadn't numbered the message yet.
     * Best effort: a miss only costs the push, the reply is saved either way.
     */
    async chatLeft(turnId, caller = {}) {
      if (!caller.login) return
      try {
        await fetchFn(`${config.jarvisApiUrl}/chat/left`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify(turnId ? { turn_id: turnId } : {}),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
      } catch {
        // Jarvis didn't hear it; nothing to tell anyone.
      }
    },

    /** Approves or denies one of Jarvis's waiting requests (POST /approve). */
    async answerApproval(id, ok, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to answer Jarvis' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/approve`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify({ id, ok }),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (res.status === 404) return goneApproval(await res.json().catch(() => null))
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, message: ok ? 'Approved' : 'Denied' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * Stops one piece of background work (POST /jobs/{id}/stop). Jarvis
     * cancels it and cleans up; 404 or 410 means it had already finished.
     */
    async stopJob(id, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to stop a job' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/jobs/${encodeURIComponent(id)}/stop`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(STOP_TIMEOUT_MS),
        })
        const said = await res.json().catch(() => null)
        if (res.status === 404 || res.status === 410) {
          return { ok: false, gone: true, message: saidText(said?.message) ?? 'That one already finished' }
        }
        if (!res.ok) return { ok: false, message: saidText(said?.message) ?? jarvisSaid(res.status) }
        return { ok: true, message: saidText(said?.detail) ?? 'Stopped' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Hide on an offer card (POST /offers/{id}/hide). */
    async hideOffer(id, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to answer Jarvis' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/offers/${encodeURIComponent(id)}/hide`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        // Already gone counts as hidden.
        if (!res.ok && res.status !== 404) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, message: 'Hidden' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Answers a "logged this already?" meal question (POST /chat/meal); the message is what Jarvis says back. */
    async answerMeal(key, choice, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to tell Jarvis' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/chat/meal`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify({ key, choice }),
          signal: AbortSignal.timeout(CHAT_TIMEOUT_MS),
        })
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        const body = await res.json()
        return { ok: true, message: typeof body?.reply === 'string' ? body.reply : 'Done' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Clear on notifications (POST /notices/clear with {ids} or {all: true}). */
    async clearNotices(which, caller = {}) {
      return postToJarvis('/notices/clear', which, caller, 'Cleared', 'Jarvis can’t keep notifications yet')
    },

    /**
     * Keep on a chat message ({turnId}) or a notice ({id}): POST /notices/keep with
     * turn_id or notice_id. The answer carries the kept notice when Jarvis sends one.
     */
    async keepNotice(what, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to tell Jarvis' }
      let body = { notice_id: what.id }
      if (what.turnId !== undefined) body = { turn_id: what.turnId }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/notices/keep`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        // 404 with a JSON answer = no such message; without one, a Jarvis too old to keep things.
        const answer = await res.json().catch(() => null)
        if (res.status === 404 && answer?.ok === false) return { ok: false, message: 'Jarvis can’t find that message' }
        if (res.status === 404) return { ok: false, message: 'Jarvis can’t keep messages yet' }
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        const result = { ok: true, message: 'Kept' }
        const notice = parseNotice(answer?.notice)
        if (notice !== null) result.notice = notice
        return result
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Letting a kept one go (POST /notices/unkeep with {id}). */
    async unkeepNotice(id, caller = {}) {
      return postToJarvis('/notices/unkeep', { id }, caller, 'Let go', 'Jarvis can’t keep messages yet')
    },

    /** An app's push token (POST /push/register), so Jarvis can notify that device. */
    async registerPush(device, caller = {}) {
      return postToJarvis('/push/register', device, caller, 'Registered', 'Jarvis can’t send notifications yet')
    },

    /** Tells Jarvis you've gone to bed or are up (POST /sleep); an older Jarvis answers 404. */
    async setSleep(asleep, from, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to tell Jarvis' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/sleep`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify({ asleep, source: from }),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (res.status === 404) return { ok: false, message: 'Jarvis can’t track sleep yet' }
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, message: asleep ? 'Good night' : 'Good morning' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** "That was wrong" on one of his web chat replies (POST /feedback). */
    async sendFeedback(flag, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to tell Jarvis' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/feedback`, {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'tailscale-user-login': caller.login },
          body: JSON.stringify({ ...flag, at: new Date().toISOString(), chat: 'web' }),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (res.status === 404) return { ok: false, message: 'This Jarvis can’t take corrections yet' }
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, message: 'Thanks. Jarvis will work on it tonight.' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Jarvis's requests still waiting for an answer (GET /approvals); empty if unreachable. */
    async approvals(caller = {}) {
      if (!caller.login) return []
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/approvals`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return []
        const body = await res.json()
        if (!Array.isArray(body?.pending)) return []
        return body.pending.map(toApproval).filter(Boolean)
      } catch {
        return []
      }
    },

    /**
     * One page of the web chat from Jarvis (GET /chat/history), oldest first:
     * the newest turns, or the ones before or around a turn id. Empty if unreachable.
     */
    async history(caller, page) {
      if (!caller.login) return emptyHistory()
      try {
        // No page asked for: the newest turns, as before paging existed.
        const query = historyQuery(page ?? { limit: HISTORY_DEFAULT })
        const res = await fetchFn(`${config.jarvisApiUrl}/chat/history?${query}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return emptyHistory()
        return parseHistory(await res.json())
      } catch {
        return emptyHistory()
      }
    },

    /**
     * What Jarvis remembers (GET /memory/facts): his notes file as a list,
     * never memory.md. Null when there's no login or he doesn't answer.
     */
    async memory(caller = {}) {
      if (!caller.login) return null
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/memory/facts`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return null
        const body = await res.json()
        const facts = Array.isArray(body?.facts) ? body.facts.filter((f) => typeof f?.id === 'string' && typeof f?.text === 'string') : []
        return {
          facts: facts.map((f) => ({ id: f.id, text: f.text, learned: String(f.learned ?? ''), from: f.from === 'you' ? 'you' : 'nightly' })),
          turns: Number(body?.turns) || 0,
          lastDistill: typeof body?.lastDistill === 'string' ? body.lastDistill : null,
        }
      } catch {
        return null
      }
    },

    /** One day of the meal log, items and all (Jarvis GET /nutrition/day), as the caller; null when he can't be asked. `date` '' = today. */
    async nutritionDay(date, caller = {}) {
      if (!caller.login) return null
      try {
        const query = date ? `?date=${encodeURIComponent(date)}` : ''
        const res = await fetchFn(`${config.jarvisApiUrl}/nutrition/day${query}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return null
        return parseNutritionDay(await res.json())
      } catch {
        return null
      }
    },

    /** Seven days of calories against the goal (Jarvis GET /nutrition/week), as the caller; null when he can't be asked. `start` '' = this week. */
    async nutritionWeek(start, caller = {}) {
      if (!caller.login) return null
      try {
        const query = start ? `?start=${encodeURIComponent(start)}` : ''
        const res = await fetchFn(`${config.jarvisApiUrl}/nutrition/week${query}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return null
        return parseNutritionWeek(await res.json())
      } catch {
        return null
      }
    },

    /** `count` days of the meal log ending at `end` ('' = today), newest first (Jarvis GET /nutrition/days), as the caller; null when he can't be asked. */
    async nutritionDays(end, count, caller = {}) {
      if (!caller.login) return null
      try {
        let query = `?count=${count}`
        if (end) query += `&end=${encodeURIComponent(end)}`
        const res = await fetchFn(`${config.jarvisApiUrl}/nutrition/days${query}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS * 2),
        })
        if (!res.ok) return null
        return parseNutritionDays(await res.json())
      } catch {
        return null
      }
    },

    /** One meal's photo, or its thumbnail (Jarvis GET /nutrition/photo/{id}, ?size=thumb), as the caller. `gone` when that meal has none. */
    async mealPhoto(id, thumb, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to see meal photos' }
      try {
        const query = thumb ? '?size=thumb' : ''
        const res = await fetchFn(`${config.jarvisApiUrl}/nutrition/photo/${encodeURIComponent(id)}${query}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS * 2),
        })
        if (res.status === 404) return { ok: false, gone: true, message: 'No photo for that meal' }
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, type: photoType(res.headers.get('content-type')), bytes: new Uint8Array(await res.arrayBuffer()) }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /** Searches past conversations (GET /memory/search); empty when unreachable. */
    async searchMemory(query, caller = {}) {
      if (!caller.login || !query.trim()) return []
      try {
        const url = `${config.jarvisApiUrl}/memory/search?q=${encodeURIComponent(query.trim())}&limit=8`
        const res = await fetchFn(url, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return []
        const body = await res.json()
        const hits = Array.isArray(body?.hits) ? body.hits : []
        return hits
          .filter((h) => typeof h?.text === 'string')
          .map((h) => ({ chat: String(h.chat ?? ''), role: h.role === 'user' ? 'user' : 'jarvis', text: h.text, at: String(h.at ?? '') }))
      } catch {
        return []
      }
    },

    /** Remembers or forgets one fact (POST /memory/facts). */
    async changeMemory(change, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to change what Jarvis remembers' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/memory/facts`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login, 'content-type': 'application/json' },
          body: JSON.stringify(change),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        const body = await res.json().catch(() => ({}))
        if (!res.ok) return { ok: false, message: body?.message ?? jarvisSaid(res.status) }
        return { ok: true, message: body?.message ?? 'Done' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * One report's HTML (GET /reports/{id}), as Jarvis saved it. `gone` when
     * it was deleted or has expired; neither when he isn't answering.
     */
    async reportHtml(id, caller = {}) {
      if (!caller.login) return { html: null, gone: false }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/reports/${encodeURIComponent(id)}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(REPORT_TIMEOUT_MS),
        })
        if (res.status === 404) return { html: null, gone: true }
        if (!res.ok) return { html: null, gone: false }
        return { html: await res.text(), gone: false }
      } catch {
        return { html: null, gone: false }
      }
    },

    /**
     * Keeps a report past its 30 days or lets it go again (POST
     * /reports/{id}/keep), or deletes it now (POST /reports/{id}/delete).
     */
    async changeReport(change, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to change reports' }
      const id = encodeURIComponent(change.id)
      let path = `/reports/${id}/delete`
      let body = {}
      if (change.op === 'keep') {
        path = `/reports/${id}/keep`
        body = { keep: change.keep }
        if (change.days !== undefined) body = { days: change.days }
      }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}${path}`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login, 'content-type': 'application/json' },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        const answer = await res.json().catch(() => ({}))
        if (res.status === 404) return { ok: false, message: 'That report is already gone' }
        if (!res.ok) return { ok: false, message: answer?.error ?? jarvisSaid(res.status) }
        if (change.op === 'delete') return { ok: true, message: 'Deleted' }
        const report = parseReport(answer?.report)
        const message = keepMessage(change)
        if (report === null) return { ok: true, message }
        return { ok: true, message, report }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * Jarvis's playbooks and what their steps can use (GET /playbooks). Null
     * when there's no login, he doesn't answer, or he's too old to have them.
     */
    async playbooks(caller = {}) {
      if (!caller.login) return null
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/playbooks`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return null
        return parsePlaybookBook(await res.json())
      } catch {
        return null
      }
    },

    /**
     * Saves (POST /playbooks), deletes (POST /playbooks/{id}/delete) or runs
     * (POST /playbooks/{id}/run) one playbook. A run can take a while (lights,
     * a TV waking up, a step he has to think through), so it gets a longer
     * wait than a save, and comes back with how its done checklist came out.
     */
    async changePlaybook(change, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to change playbooks' }
      let path = '/playbooks'
      let body = {}
      let done = 'Saved'
      let wait = PROBE_TIMEOUT_MS * 2
      if (change.op === 'save') body = { playbook: toJarvisPlaybook(change.playbook) }
      if (change.op === 'delete') {
        path = `/playbooks/${encodeURIComponent(change.id)}/delete`
        done = 'Deleted'
      }
      if (change.op === 'run') {
        path = `/playbooks/${encodeURIComponent(change.id)}/run`
        done = 'Done'
        wait = PLAYBOOK_RUN_TIMEOUT_MS
      }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}${path}`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login, 'content-type': 'application/json' },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(wait),
        })
        const answer = await res.json().catch(() => ({}))
        if (res.status === 404 && change.op === 'save') return { ok: false, message: 'Jarvis can’t run playbooks yet' }
        const said = answer?.detail ?? answer?.message ?? answer?.error
        const result = { ok: res.ok && answer?.ok !== false, message: typeof said === 'string' && said ? said : done }
        if (!result.ok && !said) result.message = jarvisSaid(res.status)
        if (change.op === 'run' && Array.isArray(answer?.checks)) result.checks = parseChecks(answer.checks)
        return result
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * Has Jarvis write a playbook from a few plain words (POST
     * /playbooks/draft). He thinks it through, so it gets a long wait. Nothing
     * is saved: the draft goes back to the editor to look over.
     */
    async draftPlaybook(text, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to write playbooks' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/playbooks/draft`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login, 'content-type': 'application/json' },
          body: JSON.stringify({ text }),
          signal: AbortSignal.timeout(PLAYBOOK_DRAFT_TIMEOUT_MS),
        })
        const answer = await res.json().catch(() => ({}))
        if (res.status === 404) return { ok: false, message: 'Jarvis can’t draft playbooks yet. Fill it in below.' }
        const playbook = fromJarvisDraft(answer?.playbook)
        if (res.ok && answer?.ok !== false && playbook !== null) return { ok: true, playbook }
        const said = answer?.message ?? answer?.detail ?? answer?.error
        return { ok: false, message: typeof said === 'string' && said ? said : 'Jarvis couldn’t write that one. Fill it in below.' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * How Jarvis sounds (GET /voice): his voice, speed, blend and every
     * voice he has. Null when there's no login or he doesn't answer.
     */
    async voice(caller = {}) {
      if (!caller.login) return null
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/voice`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        if (!res.ok) return null
        const body = await res.json()
        const voices = Array.isArray(body?.voices) ? body.voices.filter((v) => typeof v?.id === 'string') : []
        if (typeof body?.voice !== 'string' || voices.length === 0) return null
        let blend = null
        if (typeof body.blend?.voice2 === 'string') blend = { voice2: body.blend.voice2, mix: Number(body.blend.mix) || 0.5 }
        return {
          voice: body.voice,
          speed: Number(body.speed) || 1,
          blend,
          voices: voices.map((v) => ({
            id: v.id,
            name: typeof v.name === 'string' && v.name ? v.name : v.id,
            accent: v.accent === 'gb' ? 'gb' : 'us',
            gender: v.gender === 'f' ? 'f' : 'm',
          })),
        }
      } catch {
        return null
      }
    },

    /** Saves how Jarvis sounds (POST /voice); he uses it from his next reply. */
    async setVoice(choice, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to change Jarvis’s voice' }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/voice`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login, 'content-type': 'application/json' },
          body: JSON.stringify(choice),
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        const body = await res.json().catch(() => ({}))
        if (!res.ok) return { ok: false, message: body?.message ?? jarvisSaid(res.status) }
        return { ok: true, message: body?.message ?? 'Saved' }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * A spoken sample (GET /voice/sample, WAV). Longer timeout than other
     * calls: the first sample of a voice is made on the spot.
     */
    async voiceSample(choice, caller = {}) {
      if (!caller.login) return { ok: false, message: 'Open this page through Tailscale to hear Jarvis' }
      const params = new URLSearchParams({ voice: choice.voice, speed: String(choice.speed) })
      if (choice.blend) {
        params.set('voice2', choice.blend.voice2)
        params.set('mix', String(choice.blend.mix))
      }
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/voice/sample?${params}`, {
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(SAMPLE_TIMEOUT_MS),
        })
        if (!res.ok) return { ok: false, message: jarvisSaid(res.status) }
        return { ok: true, audio: new Uint8Array(await res.arrayBuffer()) }
      } catch {
        return { ok: false, message: 'Jarvis is not answering' }
      }
    },

    /**
     * Asks Jarvis to start the web chat's Claude engine now (POST
     * /chat/warm, no model call), so the first question doesn't pay for
     * starting it. True when Jarvis said yes.
     */
    async warm(caller = {}) {
      if (!caller.login) return false
      try {
        const res = await fetchFn(`${config.jarvisApiUrl}/chat/warm`, {
          method: 'POST',
          headers: { 'tailscale-user-login': caller.login },
          signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
        })
        return res.ok
      } catch {
        return false
      }
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

/**
 * Reads a streamed body of newline-separated JSON objects, yielding each
 * one as soon as its line is complete. Blank or broken lines are skipped.
 */
async function* readJsonLines(body) {
  const decoder = new TextDecoder()
  let buffer = ''
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true })
    let newline = buffer.indexOf('\n')
    while (newline !== -1) {
      const line = buffer.slice(0, newline).trim()
      buffer = buffer.slice(newline + 1)
      if (line) {
        try { yield JSON.parse(line) } catch { /* not JSON; skip it */ }
      }
      newline = buffer.indexOf('\n')
    }
  }
  const last = buffer.trim()
  if (last) {
    try { yield JSON.parse(last) } catch { /* not JSON; skip it */ }
  }
}
