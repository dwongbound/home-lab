// Mock source: believable numbers for jarvis, so the page can be built and
// reviewed before anything on the PC is wired up. It returns the same
// Snapshot shape as the live source (see src/types.ts).
//
// It also keeps a tiny bit of state (is the local model loaded?) so the Unload and
// Load buttons visibly do something in the preview.

import { createPickStore } from '../money-picks.mjs'
import { SAMPLE_VOICES, sampleWav } from '../voice.mjs'

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
/**
 * What Jarvis is doing in the background, shaped like the live source's
 * parseJobs output: the three main jobs plus the quiet housekeeping.
 */
function mockJobs(t, minutesAgo) {
  const minutesAhead = (min) => new Date(t.getTime() + min * 60_000).toISOString()
  return {
    generatedAt: t.toISOString(),
    jobs: [
      { id: 'lookout', name: 'Lookout', group: 'main', model: 'ornith-1.5:9b', schedule: 'Every 30 min while you’re awake', status: 'ok', lastRun: minutesAgo(11), nextRun: minutesAhead(19), lastResult: 'Checked the drive to volleyball and the weather there; nothing worth a ping.' },
      { id: 'messenger', name: 'Messenger', group: 'main', model: 'claude-opus-5-5', schedule: 'Whenever Lookout raises something, plus the 6 PM digest', status: 'ok', lastRun: minutesAgo(95), nextRun: null, lastResult: 'Sent: leave by 7:05 for Si! Mon.' },
      { id: 'nightly', name: 'Nightly', group: 'main', model: 'claude-opus-5-5', schedule: 'Every night at 3:30 AM', status: 'ok', lastRun: minutesAgo(600), nextRun: minutesAhead(840), lastResult: 'Saved 4 new facts and 2 to-dos, and planned tomorrow.' },
      { id: 'housekeeping-page', name: 'Home page summary', group: 'housekeeping', model: 'claude-haiku-5-5', schedule: 'Hourly, 7 AM to 11 PM', status: 'ok', lastRun: minutesAgo(24), nextRun: minutesAhead(36), lastResult: null },
      { id: 'housekeeping-nutrition', name: 'Nutrition sync', group: 'housekeeping', model: null, schedule: 'Hourly', status: 'ok', lastRun: minutesAgo(40), nextRun: minutesAhead(20), lastResult: null },
      { id: 'housekeeping-google', name: 'Google sign-in check', group: 'housekeeping', model: null, schedule: 'Every 10 min, 8 AM to 10 PM', status: 'ok', lastRun: minutesAgo(3), nextRun: minutesAhead(7), lastResult: null },
    ],
    lookout: {
      checks: ['drive_time', 'place_weather', 'calendar'],
      watching: ['Volleyball at 8 PM: light rain possible after 7'],
      heldBack: [{ text: 'SPY down 0.8%', reason: 'A normal move, not worth a ping.' }],
    },
    messenger: { sentToday: 2, cap: 5, quiet: null },
    running: [
      { id: 'r1', label: 'Making drive times mention parking', state: 'running', startedAt: minutesAgo(2) },
      { id: 'r2', label: 'Saying traffic first', state: 'queued', startedAt: null },
    ],
  }
}

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
        { id: 'x9', date: minutesAgo(3600), merchant: 'Online Transfer To Chk', category: '', amount: 500, account: 'Savings', accountId: 'm2', type: 'transfer' },
        { id: 'x4', date: minutesAgo(4300), merchant: 'Spotify', category: 'Subscriptions', amount: 11.99, account: 'Sapphire', accountId: 'm3' },
        { id: 'x6', date: minutesAgo(5800), merchant: 'Amazon', category: '', amount: 34.5, account: 'Sapphire', accountId: 'm3' },
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
// How long the sample Jarvis waits for an approval, like the real one (10 minutes).
const APPROVAL_WAIT_MS = 600_000

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
    // The pretend web chat with Jarvis, oldest first.
    chat: [],
    // Approvals the pretend Jarvis is waiting on: id -> {approval, answer(ok)}.
    approvals: new Map(),
    nextApproval: 1,
    // Pretend things Jarvis remembers (made up: this repo is public).
    facts: sampleFacts(now()),
    nextFactId: 100,
    // How the pretend Jarvis sounds; the Voice section changes it.
    voice: { voice: 'bm_george', speed: 1, blend: null },
    // When a pretend digest refresh finishes (ms), so the page's
    // "Updating from Jarvis…" can be seen and then clear.
    digestReadyAt: 0,
    // When the last finished one finished, so a new one doesn't hide it.
    digestDoneAt: 0,
    // Sample devices for the Home page. Its buttons change these.
    home: [
      { id: 'climate.thermostat', name: 'Thermostat', kind: 'climate', state: 'heat', available: true, current: 68, target: 70, min: 50, max: 90, step: 1, modes: ['off', 'heat', 'cool', 'heat_cool'] },
      { id: 'light.living_room_lamp', name: 'Living room lamp', kind: 'light', state: 'on', available: true, brightness: 0.6 },
      { id: 'switch.porch_lights', name: 'Porch lights', kind: 'switch', state: 'off', available: true },
      { id: 'media_player.bedroom', name: 'Bedroom speaker', kind: 'media', state: 'playing', available: true, volume: 0.25, detail: 'Hillsong UNITED · Oceans' },
      { id: 'media_player.apple_tv', name: 'Apple TV', kind: 'media', state: 'off', available: true },
      { id: 'media_player.tv', name: 'TV', kind: 'media', state: 'unavailable', available: false },
      { id: 'scene.movie_night', name: 'Movie night', kind: 'scene', state: 'scening', available: true },
    ],
  }
  // Categories picked on the Money page, in memory.
  const picks = createPickStore({ now })

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

      const cloud = withRefresh(mockDigest(t, minutesAgo), state)
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
          { id: 't5', at: atPacificTime(t, 23, 30), title: 'Local model unloads if idle', detail: 'Frees about 6 GB of GPU memory', status: 'scheduled' },
        ],
        activity: [
          { id: 'a1', at: minutesAgo(4), kind: 'jarvis', text: 'Jarvis answered "what time is sunset" on Telegram' },
          { id: 'a2', at: minutesAgo(38), kind: 'ha', text: 'Living room lamp turned off by the bedtime scene' },
          { id: 'a3', at: minutesAgo(95), kind: 'ollama', text: 'ornith-1.5:9b loaded in 41 s' },
          { id: 'a4', at: minutesAgo(240), kind: 'system', text: 'Ubuntu started by the "Start Ubuntu (WSL)" task' },
          { id: 'a5', at: minutesAgo(610), kind: 'jarvis', text: 'Fantasy pickup run failed with an import error' },
        ],
        services: [
          { id: 'ha', name: 'Home Assistant', detail: '2026.10.2 in Docker', status: 'up', latencyMs: 14, url: 'http://192.168.68.94:8123' },
          { id: 'ollama', name: 'Ollama', detail: loaded ? 'ornith-1.5:9b loaded' : 'No model loaded', status: 'up', latencyMs: 3 },
          { id: 'jarvis', name: 'Jarvis', detail: 'Running, code changed since start', status: 'degraded', latencyMs: 22, url: 'https://jarvis.snakebird-ph.ts.net:8443' },
        ],
        model: { name: 'ornith-1.5:9b', loaded, vramGb: loaded ? 5.7 : 0, loadSeconds: 41 },
        // Like jarvis: the one local model, unloading after 10 idle minutes.
        models: loaded
          ? [{ name: 'ornith-1.5:9b', role: 'watch', vramGb: 5.7, until: new Date(t.getTime() + 8 * 60_000).toISOString(), parameters: '9.7B', quantization: 'Q4_K_M', contextLength: 8192 }]
          : [],
        cloud,
        home: {
          devices: state.home.map((d) => ({ ...d })),
          weather: { condition: 'partlycloudy', temperature: 61, unit: '°F' },
          sun: { rising: atPacificTime(t, 6, 41), setting: atPacificTime(t, 16, 52) },
        },
        jobs: mockJobs(t, minutesAgo),
        moneyPicks: await picks.read(cloud.money.recent),
      }
    },

    /** Saves, clears or re-times Money page category picks, in memory. */
    async money(change) {
      return picks.change(change)
    },

    /** Pretends to load or unload the local model, taking long enough to see the spinner. */
    async action(name) {
      if (name === 'ollama-unload') {
        await delay(1200)
        state.modelLoaded = false
        return { ok: true, message: 'Local model unloaded' }
      }
      if (name === 'ollama-load') {
        await delay(1800)
        state.modelLoaded = true
        return { ok: true, message: 'Local model loaded' }
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
      else if (command === 'target' && device.kind === 'climate' && typeof value === 'number') device.target = Math.min(device.max, Math.max(device.min, value))
      else if (command === 'mode' && device.kind === 'climate' && device.modes.includes(value)) device.state = value
      else if (command !== 'run') return { ok: false, message: `Can't ${command} that` }
      return { ok: true, message: 'Done' }
    },

    /** The pretend voice settings and the sample voice list. */
    async voice() {
      return { ...state.voice, voices: SAMPLE_VOICES }
    },

    /** Saves the pretend voice, refusing voices that aren't in the list. */
    async setVoice(choice) {
      const known = new Set(SAMPLE_VOICES.map((v) => v.id))
      if (!known.has(choice.voice) || (choice.blend && !known.has(choice.blend.voice2))) {
        return { ok: false, message: 'Jarvis doesn’t have that voice' }
      }
      state.voice = { voice: choice.voice, speed: choice.speed, blend: choice.blend }
      return { ok: true, message: 'Saved. Jarvis sounds like this from his next reply.' }
    },

    /** A made-up sample sound (sample data has no Kokoro). */
    async voiceSample(choice) {
      await delay(300)
      return { ok: true, audio: sampleWav(choice) }
    },

    /** Answers a waiting sample approval; unknown ids were already answered. */
    async answerApproval(id, ok) {
      const waiting = state.approvals.get(id)
      if (!waiting) return { ok: false, message: 'That request was already answered or ran out of time' }
      waiting.answer(ok, 'page')
      return { ok: true, message: ok ? 'Approved' : 'Denied' }
    },

    /** Sample approvals still waiting. */
    async approvals() {
      return [...state.approvals.values()].map((w) => w.approval)
    },

    /** Sample data has no engine to start. */
    async warm() {
      return true
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
      return { ok: true, message: sampleReply(text) }
    },

    /**
     * Pretends to be Jarvis's streaming chat: thinks for a moment, then
     * hands the reply over a word at a time, and keeps the conversation
     * so history() can give it back like the PC does.
     */
    async chat(text, _caller, onEvent) {
      const at = new Date().toISOString()
      state.chat.push({ role: 'user', text, at })
      await delay(700)
      // A question that needs a lookup shows the orb's working sweep first, like the real Jarvis.
      const work = sampleWork(text)
      if (work) {
        onEvent({ type: 'working', label: work })
        await delay(1800)
        onEvent({ type: 'working_done' })
      }
      let reply = sampleReply(text)
      // Asking him to change a file or run something shows the approval
      // card, and his reply waits for the answer like the real Jarvis.
      const action = sampleAction(text)
      if (action) {
        const approval = {
          id: `a${state.nextApproval++}`,
          tool: action.tool,
          summary: action.summary,
          expires: new Date(Date.now() + APPROVAL_WAIT_MS).toISOString(),
        }
        const ok = await new Promise((resolve) => {
          const timer = setTimeout(() => answer(false, 'timeout'), APPROVAL_WAIT_MS)
          /** Settles this approval once, from the page or the timeout. */
          function answer(yes, by) {
            clearTimeout(timer)
            state.approvals.delete(approval.id)
            onEvent({ type: 'approval_done', id: approval.id, ok: yes, by })
            resolve(yes)
          }
          state.approvals.set(approval.id, { approval, answer })
          onEvent({ type: 'approval', approval })
        })
        reply = ok ? `Sample data: done. ${action.done}` : 'Sample data: okay, I left it alone.'
      }
      for (const piece of reply.split(/(?<=\s)/)) {
        onEvent({ type: 'delta', text: piece })
        await delay(45)
      }
      state.chat.push({ role: 'jarvis', text: reply, at: new Date().toISOString() })
      onEvent({ type: 'done', ok: true })
    },

    /** The sample conversation so far, oldest first. */
    async history() {
      return state.chat.slice(-50)
    },

    /** The pretend facts, newest first, and a made-up count of saved turns. */
    async memory() {
      const facts = [...state.facts].sort((a, b) => b.learned.localeCompare(a.learned))
      const lastDistill = new Date(now().getTime() - 7 * 3600_000).toISOString()
      return { facts, turns: 1284 + state.chat.length, lastDistill }
    },

    /** Finds sample past moments containing the words searched for. */
    async searchMemory(query) {
      const words = query.toLowerCase().split(/\s+/).filter(Boolean)
      if (words.length === 0) return []
      const all = [...sampleHits(now()), ...state.chat.map((t) => ({ chat: 'web', role: t.role, text: t.text, at: t.at }))]
      return all.filter((h) => words.some((w) => h.text.toLowerCase().includes(w))).slice(0, 8)
    },

    /** Remembers or forgets one pretend fact. */
    async changeMemory(change) {
      if (change?.op === 'remember' && typeof change.text === 'string' && change.text.trim()) {
        state.facts.push({ id: `f${state.nextFactId++}`, text: change.text.trim(), learned: now().toISOString(), from: 'you' })
        return { ok: true, message: 'Jarvis will remember that' }
      }
      if (change?.op === 'forget') {
        const before = state.facts.length
        state.facts = state.facts.filter((f) => f.id !== change.id)
        if (state.facts.length < before) return { ok: true, message: 'Forgotten' }
        return { ok: false, message: 'Jarvis didn’t have that one' }
      }
      return { ok: false, message: 'Send {"op": "remember", "text"} or {"op": "forget", "id"}' }
    },
  }
}

/** Made-up facts for the sample memory, learned over the last few days. */
function sampleFacts(t) {
  const daysAgo = (d) => new Date(t.getTime() - d * 86_400_000).toISOString()
  return [
    { id: 'f1', text: 'Calls the living room lamp "the big light".', learned: daysAgo(0.3), from: 'nightly' },
    { id: 'f2', text: 'Wants weather in °F and wind in knots.', learned: daysAgo(1.3), from: 'nightly' },
    { id: 'f3', text: 'Plays volleyball on Tuesday nights; a rain warning before 6 pm is useful.', learned: daysAgo(2.3), from: 'nightly' },
    { id: 'f4', text: 'Prefers short answers out loud, details in text.', learned: daysAgo(3), from: 'you' },
    { id: 'f5', text: 'Unloads the local model before gaming.', learned: daysAgo(5.3), from: 'nightly' },
  ]
}

/** Made-up past moments for the sample memory search. */
function sampleHits(t) {
  const daysAgo = (d) => new Date(t.getTime() - d * 86_400_000).toISOString()
  return [
    { chat: 'telegram', role: 'user', text: 'Remind me to check the weather before volleyball on Tuesday', at: daysAgo(2.4) },
    { chat: 'voice', role: 'jarvis', text: 'The big light is on at 60 percent.', at: daysAgo(0.5) },
    { chat: 'web', role: 'user', text: 'Turn the big light off when I start gaming', at: daysAgo(4.1) },
    { chat: 'siri', role: 'jarvis', text: "Tomorrow looks clear, 68 and light wind, good flying weather.", at: daysAgo(6.2) },
  ]
}

/**
 * The sample "write a file" or "run a command" a question asks for, or null.
 * Real Jarvis decides this himself; here a few words stand in for it.
 */
function sampleAction(text) {
  const q = text.toLowerCase()
  // Asking him to change himself: one plain question, no file paths.
  if (q.includes('your code') || q.includes('change yourself')) {
    return { tool: 'change_code', summary: 'Is it OK if I change my code so drive times mention parking?', done: 'Starting that now. I’ll tell you when it’s ready.' }
  }
  if (q.includes('run ') || q.includes('restart')) {
    return { tool: 'run_command', summary: 'sudo systemctl restart jarvis', done: 'Jarvis restarted.' }
  }
  if (q.includes('write') || q.includes('edit') || q.includes('note')) {
    return { tool: 'edit_file', summary: 'edit ~/notes/todo.md (1 lines)\n+ - Book the rental car for Dallas', done: 'The note is saved.' }
  }
  return null
}

/**
 * A canned reply for the preview, so the chat has something real-sounding
 * to type out. A few topics get a longer answer; anything else says where
 * the real one would come from.
 */
/** The status line for a sample question that needs a lookup, or null. */
function sampleWork(text) {
  const q = text.toLowerCase()
  if (q.includes('traffic') || q.includes('drive')) return 'Checking traffic.'
  if (q.includes('today') || q.includes('schedule') || q.includes('calendar')) return 'Checking your calendar.'
  if (q.includes('weather')) return 'Checking the weather.'
  return null
}

function sampleReply(text) {
  const q = text.toLowerCase()
  if (q.includes('traffic') || q.includes('drive')) {
    return 'Sample data: about 35 minutes to Disneyland right now, heavier than usual on the 5. Leave by 6:10 to make a 7 o’clock entry.'
  }
  if (q.includes('light') || q.includes('lamp')) {
    return 'Sample data: the living room lamp is on at 60%, and the porch light turns on at sunset, around 4:55 tonight. Want me to switch the lamp off?'
  }
  if (q.includes('today') || q.includes('schedule') || q.includes('calendar')) {
    return 'Sample data: you have volleyball at 7:30 tonight and a study block for the written test at 10. Nothing else until tomorrow morning.'
  }
  if (q.includes('weather')) {
    return 'Sample data: 68 and clear in West LA right now, dropping to 55 overnight. Light wind at Torrance, good flying weather tomorrow morning.'
  }
  return `Sample data: on the PC, Jarvis would answer "${text}" here.`
}
