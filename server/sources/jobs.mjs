// Jarvis's background jobs (GET /jobs on its local API), cleaned up for the
// page: Lookout (ornith, every 30 min), Messenger (Claude, everything that
// reaches Dylan), Nightly (Opus at 3:30 AM) and the quiet housekeeping.
// Jarvis writes snake_case; the page uses camelCase. Anything malformed is
// dropped rather than shown half-broken.

const STATUSES = new Set(['ok', 'running', 'error', 'paused'])
const MAX_LIST = 12

/** A string, or null when it's missing or not text. */
function text(value) {
  if (typeof value === 'string' && value.trim() !== '') return value.trim()
  return null
}

/** An ISO time string the browser can parse, or null. */
function time(value) {
  if (typeof value !== 'string') return null
  if (Number.isNaN(Date.parse(value))) return null
  return value
}

/** The plain strings in a list, at most MAX_LIST of them. */
function texts(list) {
  if (!Array.isArray(list)) return []
  const out = []
  for (const item of list) {
    const t = text(item)
    if (t !== null) out.push(t)
  }
  return out.slice(0, MAX_LIST)
}

/** One job, or null when it has no id or name. */
function parseJob(raw) {
  const id = text(raw?.id)
  const name = text(raw?.name)
  if (id === null || name === null) return null
  let status = 'ok'
  if (STATUSES.has(raw.status)) status = raw.status
  let group = 'main'
  if (raw.group === 'housekeeping') group = 'housekeeping'
  return {
    id,
    name,
    group,
    model: text(raw.model),
    schedule: text(raw.schedule),
    status,
    lastRun: time(raw.last_run),
    nextRun: time(raw.next_run),
    lastResult: text(raw.last_result),
  }
}

/** What Lookout looked at, is keeping an eye on and decided not to send. */
function parseLookout(raw) {
  if (raw === null || typeof raw !== 'object') return null
  const heldBack = []
  if (Array.isArray(raw.held_back)) {
    for (const item of raw.held_back) {
      const t = text(item?.text)
      if (t !== null) heldBack.push({ text: t, reason: text(item.reason) })
    }
  }
  return { checks: texts(raw.checks), watching: texts(raw.watching), heldBack: heldBack.slice(0, MAX_LIST) }
}

/** How many pings went out today against the cap, and why it's quiet if it is. */
function parseMessenger(raw) {
  if (raw === null || typeof raw !== 'object') return null
  if (!Number.isInteger(raw.sent_today) || !Number.isInteger(raw.cap)) return null
  return { sentToday: raw.sent_today, cap: raw.cap, quiet: text(raw.quiet) }
}

/**
 * The work Dylan sent off to run in the background (a change to Jarvis's
 * code, say), still going or waiting its turn. Finished ones aren't listed.
 */
function parseRunning(list) {
  if (!Array.isArray(list)) return []
  const out = []
  for (const raw of list) {
    const id = text(raw?.id)
    const label = text(raw?.label)
    if (id === null || label === null) continue
    let state = 'running'
    if (raw.state === 'queued') state = 'queued'
    out.push({ id, label, state, startedAt: time(raw.started_at) })
  }
  return out.slice(0, MAX_LIST)
}

/** The whole /jobs answer for the page, or null when it isn't one. */
export function parseJobs(body) {
  if (body === null || typeof body !== 'object' || !Array.isArray(body.jobs)) return null
  const jobs = []
  for (const raw of body.jobs) {
    const job = parseJob(raw)
    if (job !== null) jobs.push(job)
  }
  return {
    generatedAt: time(body.generated_at),
    jobs,
    lookout: parseLookout(body.lookout),
    messenger: parseMessenger(body.messenger),
    running: parseRunning(body.running),
  }
}
