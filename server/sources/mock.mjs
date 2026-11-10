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
      { id: 'c1', title: 'Flight block N8318B', start: atPacificTime(t, 15, 0), end: atPacificTime(t, 17, 0), allDay: false, calendar: 'VFF', location: 'Santa Monica Airport', url: 'https://calendar.google.com/calendar/r/day' },
      { id: 'c2', title: 'Worship practice', start: atPacificTime(t, 19, 30), end: atPacificTime(t, 21, 0), allDay: false, calendar: 'Church' },
    ],
    email: [
      { id: 'e1', from: 'Google Cloud', subject: 'OAuth verification: action needed', why: 'Waiting on your scope declaration', url: 'https://mail.google.com/mail/u/0/#inbox' },
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
    // Made-up numbers in the shape the digest task writes from Copilot.
    money: {
      netWorth: 48210,
      accounts: [
        { id: 'm1', name: 'Checking', institution: 'Example Bank', kind: 'cash', balance: 6420.55 },
        { id: 'm2', name: 'Savings', institution: 'Example Bank', kind: 'cash', balance: 18250 },
        { id: 'm3', name: 'Sapphire', institution: 'Example Card Co', kind: 'credit', balance: 1284.19 },
        { id: 'm4', name: 'Brokerage', institution: 'Example Invest', kind: 'investment', balance: 24823.64 },
        // An old account with nothing in it: the page tucks these away.
        { id: 'm5', name: 'Old Checking', institution: 'Example Bank', kind: 'cash', balance: 0 },
      ],
      spending: { thisMonth: 1862.4, lastMonthToDate: 2104.75, budget: 4000 },
      categories: [
        { name: 'Food & drink', spent: 512.3, budget: 700 },
        { name: 'Shopping', spent: 388.12, budget: 400 },
        { name: 'Transport', spent: 214.6, budget: 300 },
        { name: 'Subscriptions', spent: 96.97, budget: 120 },
      ],
      recent: [
        { id: 'x1', date: minutesAgo(200), merchant: 'Trader Joe’s', category: 'Food & drink', amount: 64.18, account: 'Sapphire', accountId: 'm3' },
        // Venmo notes arrive with a stray "undefined", and land in Other until sorted.
        { id: 'x5', date: minutesAgo(900), merchant: 'Venmo Alex "undefined"', category: 'Other', amount: 120, account: 'Checking', accountId: 'm1', note: 'Lesson' },
        { id: 'x2', date: minutesAgo(1500), merchant: 'Shell', category: 'Transport', amount: 48.02, account: 'Sapphire', accountId: 'm3', pending: true },
        { id: 'x3', date: minutesAgo(2900), merchant: 'Payroll', category: 'Income', amount: -3450, account: 'Checking', accountId: 'm1' },
        { id: 'x4', date: minutesAgo(4300), merchant: 'Spotify', category: 'Subscriptions', amount: 11.99, account: 'Sapphire', accountId: 'm3' },
      ],
      flags: [
        { id: 'f1', text: 'Shopping is at 97% of its budget with 20 days to go' },
      ],
    },
  }
}

/**
 * Creates a mock source. `now` is injectable so tests can pin the clock.
 */
// How long a pretend digest refresh takes.
const MOCK_REFRESH_MS = 4000

/** The digest, stamped with the last pretend refresh that has finished. */
function withRefresh(digest, state) {
  let done = state.digestDoneAt
  if (state.digestReadyAt !== 0 && Date.now() >= state.digestReadyAt) done = state.digestReadyAt
  if (done === 0) return digest
  return { ...digest, updatedAt: new Date(done).toISOString() }
}

export function createMockSource({ now = () => new Date() } = {}) {
  const state = {
    modelLoaded: true,
    // When a pretend digest refresh finishes (ms), so the page's
    // "Updating from Jarvis…" can be seen and then clear.
    digestReadyAt: 0,
    // When the last finished one finished, so a new one doesn't hide it.
    digestDoneAt: 0,
    // Sample devices for the Home page. Its buttons change these.
    home: [
      { id: 'light.living_room_lamp', name: 'Living room lamp', kind: 'light', state: 'on', available: true, brightness: 0.6 },
      { id: 'switch.porch_lights', name: 'Porch lights', kind: 'switch', state: 'off', available: true },
      { id: 'media_player.bedroom', name: 'Bedroom speaker', kind: 'media', state: 'playing', available: true, volume: 0.25, detail: 'Hillsong UNITED · Oceans' },
      { id: 'media_player.apple_tv', name: 'Apple TV', kind: 'media', state: 'off', available: true },
      { id: 'media_player.tv', name: 'TV', kind: 'media', state: 'unavailable', available: false },
      { id: 'scene.movie_night', name: 'Movie night', kind: 'scene', state: 'scening', available: true },
    ],
  }

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
          { id: 'webui', name: 'Open WebUI', detail: 'Chat with Gemma', status: 'up', latencyMs: 41, url: 'https://jarvis.snakebird-ph.ts.net:8081' },
          { id: 'jarvis', name: 'Jarvis', detail: 'Running, code changed since start', status: 'degraded', latencyMs: 22, url: 'https://jarvis.snakebird-ph.ts.net:8443' },
        ],
        model: { name: 'Gemma 12B', loaded, vramGb: loaded ? 10.1 : 0, loadSeconds: 168 },
        cloud: withRefresh(mockDigest(t, minutesAgo), state),
        home: {
          devices: state.home.map((d) => ({ ...d })),
          weather: { condition: 'partlycloudy', temperature: 61, unit: '°F' },
          sun: { rising: atPacificTime(t, 6, 41), setting: atPacificTime(t, 16, 52) },
        },
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

    /** Pretends to control a device, so the Home page's buttons visibly work. */
    async control(entityId, command, value) {
      const device = state.home.find((d) => d.id === entityId)
      if (!device) return { ok: false, message: 'Not a device' }
      if (!device.available) return { ok: false, message: `${device.name} is unavailable` }
      await delay(400)
      if (command === 'toggle') device.state = device.state === 'on' ? 'off' : 'on'
      else if (command === 'power') device.state = device.state === 'off' ? 'idle' : 'off'
      else if (command === 'playpause') device.state = device.state === 'playing' ? 'paused' : 'playing'
      else if (command === 'brightness') { device.brightness = value; device.state = value > 0 ? 'on' : 'off' }
      else if (command === 'volume') device.volume = value
      else if (command !== 'run') return { ok: false, message: `Can't ${command} that` }
      return { ok: true, message: 'Done' }
    },

    /**
     * Pretends Jarvis rewrites the digest, taking a few seconds. An ask
     * during a run pushes its end back, so every page that asks sees the
     * "Updating" state (pages share this sample server in the tests).
     */
    async refreshDigest() {
      const t = Date.now()
      if (t >= state.digestReadyAt) state.digestDoneAt = state.digestReadyAt
      state.digestReadyAt = t + MOCK_REFRESH_MS
      let lastWrite = null
      if (state.digestDoneAt !== 0) lastWrite = new Date(state.digestDoneAt).toISOString()
      return { running: true, lastWrite }
    },

    /** Pretends to be Jarvis, so the Ask box works on sample data. */
    async ask(text) {
      await delay(900)
      return { ok: true, message: `Sample data: on the PC, Jarvis would answer "${text}" here.` }
    },
  }
}
