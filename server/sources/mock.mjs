// Mock source: believable numbers for jarvis, so the page can be built and
// reviewed before anything on the PC is wired up. It returns the same
// Snapshot shape as the live source (see src/types.ts).
//
// It also keeps a tiny bit of state (is Gemma loaded?) so the Unload and
// Load buttons visibly do something in the preview.

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const REQUESTS_PER_DAY = [14, 22, 9, 31, 26, 7, 4]
const PC_TIME_ZONE = 'America/Los_Angeles'

/**
 * A smooth, repeatable wiggle of `count` points around `base`, used for the
 * sparklines. `seed` shifts it so each card gets a different shape.
 */
function wave(seed, count, base, spread) {
  const out = []
  for (let i = 0; i < count; i++) {
    const v = base + Math.sin((i + seed) * 0.9) * spread * 0.6 + Math.cos((i + seed) * 0.37) * spread * 0.4
    out.push(Math.round(v * 10) / 10)
  }
  return out
}

/**
 * The instant that is `hour:minute` on the PC's clock (Pacific) on the same
 * Pacific calendar day as `date`. The server itself may run in UTC, so
 * Date#setHours would put the 9 am run at 1 am in the browser.
 */
export function atPacificTime(date, hour, minute) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: PC_TIME_ZONE, hourCycle: 'h23',
      year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric',
    }).formatToParts(date).map((p) => [p.type, Number(p.value)]),
  )
  // How far Pacific wall-clock time is from UTC right now (-7 h or -8 h).
  const wallClockAsUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute)
  const offsetMs = wallClockAsUtc - Math.floor(date.getTime() / 60_000) * 60_000
  const wantedAsUtc = Date.UTC(parts.year, parts.month - 1, parts.day, hour, minute)
  return new Date(wantedAsUtc - offsetMs).toISOString()
}

/** Monday = 0 ... Sunday = 6, on the PC's clock. */
function pacificWeekdayIndex(date) {
  const short = new Intl.DateTimeFormat('en-US', { timeZone: PC_TIME_ZONE, weekday: 'short' }).format(date)
  return DAYS.indexOf(short)
}

/** Delay helper for the fake actions, so the blocking spinner is visible. */
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const PROJECT_URL = 'https://claude.ai/code/project/chan_example'

/**
 * A sample cloud digest, shaped like the one the scheduled task writes
 * (docs/digest.md). Titles are examples, not real threads.
 */
function mockDigest(t, minutesAgo) {
  const thread = (id, title, state, min) => ({ id, title, state, lastActivityAt: minutesAgo(min), url: `${PROJECT_URL}?thread=${id}` })
  return {
    updatedAt: minutesAgo(12),
    threads: [
      thread('t-lab', 'Build glassy home lab admin page', 'working', 2),
      thread('t-oauth', 'Fix unverified app warning on calendar picker', 'blocked', 140),
      thread('t-fantasy', 'Fantasy basketball pickup advisor', 'blocked', 300),
      thread('t-rules', 'Make rule changes org-wide', 'review_ready', 95),
      thread('t-brief', 'Daily briefing and deal watch', 'done', 420),
      thread('t-dinner', 'Anniversary dinner shortlist', 'done', 1500),
    ],
    calendar: [
      { id: 'c1', title: 'Flight block N8318B', start: atPacificTime(t, 15, 0), end: atPacificTime(t, 17, 0), allDay: false, calendar: 'VFF' },
      { id: 'c2', title: 'Worship practice', start: atPacificTime(t, 19, 30), end: atPacificTime(t, 21, 0), allDay: false, calendar: 'Church' },
    ],
    email: [
      { id: 'e1', from: 'Google Cloud', subject: 'OAuth verification: action needed', why: 'Waiting on your scope declaration' },
      { id: 'e2', from: 'VFF Flying Club', subject: 'November dues', why: 'Due Friday' },
    ],
    deploys: [
      { project: 'tapworship.com', state: 'ready', at: minutesAgo(180), url: 'https://tapworship.com' },
      { project: 'vardafreeflyers.com', state: 'ready', at: minutesAgo(2900), url: 'https://vardafreeflyers.com' },
    ],
    pullRequests: [
      { repo: 'home-lab', number: 2, title: "Match the live source to what's really on jarvis", ci: 'passing', url: 'https://github.com/dwongbound/home-lab/pull/2' },
      { repo: 'worship-scheduler', number: 228, title: 'Calendar picker to staging', ci: 'passing', url: 'https://github.com/dwongbound/worship-scheduler/pull/228' },
    ],
  }
}

/**
 * Creates a mock source. `now` is injectable so tests can pin the clock.
 */
export function createMockSource({ now = () => new Date() } = {}) {
  const state = { modelLoaded: true }

  return {
    kind: 'mock',

    /** One made-up snapshot of the PC. */
    async snapshot() {
      const t = now()
      const seed = t.getMinutes()
      const loaded = state.modelLoaded
      const minutesAgo = (min) => new Date(t.getTime() - min * 60_000).toISOString()
      const todayIndex = pacificWeekdayIndex(t)

      // Days later in the week haven't happened yet, so they're zero.
      const requests = DAYS.map((day, i) => ({
        day,
        count: i > todayIndex ? 0 : REQUESTS_PER_DAY[i],
        today: i === todayIndex,
      }))

      return {
        generatedAt: t.toISOString(),
        source: 'mock',
        host: { name: 'jarvis', os: 'Windows 11 + Ubuntu 24.04 (WSL 2)', uptimeSec: 6 * 86400 + 4 * 3600 + 12 * 60 },
        metrics: [
          { id: 'ram', label: 'Memory', value: loaded ? 11.4 : 6.9, unit: 'GB', total: 16, history: wave(seed, 24, loaded ? 11 : 7, 1.2) },
          { id: 'gpu', label: 'GPU memory', value: loaded ? 10.1 : 0.6, unit: 'GB', total: 12, history: wave(seed + 3, 24, loaded ? 9.8 : 0.8, 0.6) },
          { id: 'cpu', label: 'Processor', value: 18, unit: '%', total: 100, history: wave(seed + 7, 24, 16, 9) },
          { id: 'disk', label: 'Free on C:', value: 93, unit: 'GB', total: 237, history: wave(seed + 1, 24, 94, 0.8) },
        ],
        requests,
        today: [
          { id: 't1', at: atPacificTime(t, 3, 0), title: 'WSL disk trim', detail: 'Reclaimed 1.8 GB', status: 'done' },
          { id: 't2', at: atPacificTime(t, 9, 0), title: 'Fantasy pickup run', detail: 'Failed: Jarvis is running old code, needs a restart', status: 'failed' },
          { id: 't3', at: atPacificTime(t, 12, 30), title: 'Home Assistant backup', detail: 'Local snapshot, 212 MB', status: 'done' },
          { id: 't4', at: atPacificTime(t, 17, 5), title: 'Porch lights on at sunset', detail: 'Home Assistant automation', status: 'scheduled' },
          { id: 't5', at: atPacificTime(t, 23, 30), title: 'Unload Gemma if idle', detail: 'Frees about 10 GB of GPU memory', status: 'scheduled' },
        ],
        activity: [
          { id: 'a1', at: minutesAgo(4), kind: 'jarvis', text: 'Jarvis answered "what time is sunset" on Telegram' },
          { id: 'a2', at: minutesAgo(38), kind: 'ha', text: 'Living room lamp turned off by the bedtime scene' },
          { id: 'a3', at: minutesAgo(95), kind: 'ollama', text: 'Gemma loaded in 2 min 48 s' },
          { id: 'a4', at: minutesAgo(240), kind: 'system', text: 'Ubuntu started by the "Start Ubuntu (WSL)" task' },
          { id: 'a5', at: minutesAgo(610), kind: 'jarvis', text: 'Fantasy pickup run failed with an import error' },
        ],
        services: [
          { id: 'ha', name: 'Home Assistant', detail: '2026.10.2 in Docker', status: 'up', latencyMs: 14, url: 'http://192.168.68.94:8123' },
          { id: 'ollama', name: 'Ollama', detail: loaded ? 'Gemma 12B loaded' : 'No model loaded', status: loaded ? 'up' : 'idle', latencyMs: 3 },
          { id: 'webui', name: 'Open WebUI', detail: 'Chat with Gemma', status: 'up', latencyMs: 41, url: 'https://jarvis.snakebird-ph.ts.net' },
          { id: 'jarvis', name: 'Jarvis', detail: 'Running, code changed since start', status: 'degraded', latencyMs: 22, url: 'https://jarvis.snakebird-ph.ts.net:8443' },
        ],
        model: { name: 'Gemma 12B', loaded, vramGb: loaded ? 10.1 : 0, loadSeconds: 168 },
        cloud: mockDigest(t, minutesAgo),
      }
    },

    /** Pretends to load or unload Gemma, taking long enough to see the spinner. */
    async action(name) {
      if (name === 'ollama-unload') {
        await delay(1200)
        state.modelLoaded = false
        return { ok: true, message: 'Gemma unloaded' }
      }
      if (name === 'ollama-load') {
        await delay(1800)
        state.modelLoaded = true
        return { ok: true, message: 'Gemma loaded' }
      }
      return { ok: false, message: `Unknown action: ${name}` }
    },

    /** Pretends to be Jarvis, so the Ask box works on sample data. */
    async ask(text) {
      await delay(900)
      return { ok: true, message: `Sample data: on the PC, Jarvis would answer "${text}" here.` }
    },
  }
}
