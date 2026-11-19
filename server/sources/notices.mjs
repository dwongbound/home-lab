// Jarvis's notifications (GET /notices on its local API): the unread things
// he wants Dylan to see, newest first. The apps show one dot on the orb per
// notice and one shared list; clearing a notice clears it on every device
// (Dylan, 2026-11-18). Jarvis writes snake_case; anything malformed is dropped.
// A notice or chat message Dylan chose to keep carries `kept: true`: it stays on
// the list (a yellow dot in the apps) until he lets it go, whatever gets cleared
// (Dylan, 2026-11-19).

const MAX_NOTICES = 30
// Kept ones come after the unread ones and have their own, roomier limit.
const MAX_KEPT = 100
const MAX_TEXT = 300
// "need" = waiting on Dylan (an approval), "heads" = worth knowing, "fyi" = just so he knows.
const KINDS = ['need', 'heads', 'fyi']
// "kept" = a chat message he asked to keep, which never was a notification.
const SOURCES = ['approval', 'lookout', 'reminder', 'alert', 'job', 'message', 'kept']
const ID = /^[\w-]{1,64}$/

/** Trimmed text cut to a card's length, or '' when it isn't text. */
function words(value) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, MAX_TEXT)
}

/** One notice, or null when it lacks an id, a known kind or a title. */
export function parseNotice(raw) {
  const id = typeof raw?.id === 'string' && ID.test(raw.id) ? raw.id : null
  const title = words(raw?.title)
  if (id === null || !KINDS.includes(raw?.kind) || title === '') return null
  const notice = { id, kind: raw.kind, title, body: words(raw.body), source: 'message', created: null }
  if (SOURCES.includes(raw.source)) notice.source = raw.source
  if (typeof raw.created === 'string' && !Number.isNaN(Date.parse(raw.created))) notice.created = raw.created
  // The approval this notice is about, so Approve and Deny can sit on its row.
  if (typeof raw.approval_id === 'string' && ID.test(raw.approval_id)) notice.approvalId = raw.approval_id
  // The chat turn holding the full message (the notice is only a preview), so a tap can open the chat there.
  if (Number.isInteger(raw.turn_id) && raw.turn_id > 0) notice.turnId = raw.turn_id
  // Kept until he lets it go; left off the ones that aren't.
  if (raw.kept === true) notice.kept = true
  return notice
}

/** Jarvis's answer as the page's list, or null when it isn't one. */
export function parseNotices(raw) {
  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.notices)) return null
  const notices = []
  let unread = 0
  let kept = 0
  for (const item of raw.notices) {
    const notice = parseNotice(item)
    if (notice === null) continue
    // Each kind is cut at its own limit, so a long unread list can't push the kept ones out.
    if (notice.kept === true) {
      kept += 1
      if (kept <= MAX_KEPT) notices.push(notice)
    } else {
      unread += 1
      if (unread <= MAX_NOTICES) notices.push(notice)
    }
  }
  return notices
}

/** Which notices to clear, from a request body: {all: true}, {ids: [...]}, or null when it's neither. */
export function parseClear(body) {
  if (body?.all === true) return { all: true }
  if (!Array.isArray(body?.ids) || body.ids.length === 0 || body.ids.length > MAX_NOTICES) return null
  for (const id of body.ids) {
    if (typeof id !== 'string' || !ID.test(id)) return null
  }
  return { ids: body.ids }
}

/**
 * What to keep, from a request body: {turnId: 12} (a chat message) or {id: "n1"}
 * (a notice already on the list), or null when it's neither.
 */
export function parseKeep(body) {
  if (Number.isInteger(body?.turnId) && body.turnId > 0) return { turnId: body.turnId }
  if (typeof body?.id === 'string' && ID.test(body.id)) return { id: body.id }
  return null
}

/** The kept notice to let go, from a request body ({id: "n1"}), or null when there's no proper id. */
export function parseUnkeep(body) {
  if (typeof body?.id === 'string' && ID.test(body.id)) return body.id
  return null
}

/** A device asking for pushes, from a request body, or null when a field is wrong. */
export function parsePushDevice(body) {
  if (typeof body?.token !== 'string' || !/^[0-9a-f]{32,200}$/i.test(body.token)) return null
  if (!['ios', 'tvos', 'watchos'].includes(body.platform)) return null
  if (!['sandbox', 'production'].includes(body.environment)) return null
  if (typeof body.bundle !== 'string' || !/^[A-Za-z0-9.-]{3,100}$/.test(body.bundle)) return null
  let name = ''
  if (typeof body.name === 'string') name = body.name.trim().slice(0, 60)
  return { token: body.token.toLowerCase(), platform: body.platform, environment: body.environment, bundle: body.bundle, name }
}
