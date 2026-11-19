// Chat history, a page at a time: the checks on what a client asks for, the
// clean-up of what Jarvis answers, and the same paging over a plain list for
// the mock. The apps load the newest turns and fetch older ones as he scrolls.

/** How many turns a request gets when it doesn't say, and the most it may ask for. */
export const HISTORY_DEFAULT = 50
export const HISTORY_MAX = 100

/** A turn id from a query string: a whole number above zero, or null. */
function turnId(value) {
  if (typeof value !== 'string' || !/^[1-9]\d{0,14}$/.test(value)) return null
  return Number(value)
}

/**
 * Reads ?limit=&before=&around= into { limit, before?, around? }; null when
 * something is off (a limit outside 1-100, an id that isn't a number, or both
 * before and around at once).
 */
export function parseHistoryPage(params) {
  const page = { limit: HISTORY_DEFAULT }
  const limit = params.get('limit')
  if (limit !== null) {
    if (!/^\d{1,3}$/.test(limit) || Number(limit) < 1 || Number(limit) > HISTORY_MAX) return null
    page.limit = Number(limit)
  }
  const before = params.get('before')
  const around = params.get('around')
  if (before !== null && around !== null) return null
  if (before !== null) {
    page.before = turnId(before)
    if (page.before === null) return null
  }
  if (around !== null) {
    page.around = turnId(around)
    if (page.around === null) return null
  }
  return page
}

/** The query string Jarvis's /chat/history takes for a page. */
export function historyQuery(page) {
  const params = new URLSearchParams({ limit: String(page.limit) })
  if (page.before) params.set('before', String(page.before))
  if (page.around) params.set('around', String(page.around))
  return params.toString()
}

/** One of Jarvis's history lines as the page's ChatTurn; null for a broken one. */
function toTurn(t) {
  if (typeof t?.text !== 'string') return null
  const turn = { role: t.role === 'user' ? 'user' : 'jarvis', text: t.text, at: String(t.at ?? '') }
  // Older Jarvis lines don't say who wrote them; the chip only shows when one does.
  if (typeof t.model === 'string' && t.model) turn.model = t.model
  // For a message he sent unasked (model "notice:lookout"): the model that wrote it.
  if (typeof t.writer === 'string' && t.writer) turn.writer = t.writer.slice(0, 80)
  // How many photos went with it (the bytes aren't in the history).
  if (Number.isInteger(t.images) && t.images > 0) turn.images = t.images
  // His number for the turn, so a notice's turnId can find the message it previews.
  if (Number.isInteger(t.id) && t.id > 0) turn.id = t.id
  // Dylan asked to keep this one (it's on the notices list until he lets it go).
  if (t.kept === true) turn.kept = true
  return turn
}

/**
 * Jarvis's /chat/history answer as { turns, hasMore, hasNewer, pending },
 * oldest first. An older Jarvis answers a bare list or no flags: then there's
 * nothing more to say than the turns.
 */
export function parseHistory(body) {
  const list = Array.isArray(body) ? body : body?.turns
  const turns = Array.isArray(list) ? list.map(toTurn).filter(Boolean) : []
  return {
    turns,
    // Older turns than the first one here exist, so scrolling up can fetch them.
    hasMore: body?.has_more === true,
    // Only with ?around=: newer turns than the last one here exist.
    hasNewer: body?.has_newer === true,
    // Jarvis is still writing the reply to the newest turn.
    pending: body?.pending === true,
  }
}

/** Nothing to show: no login, or Jarvis didn't answer. */
export function emptyHistory() {
  return { turns: [], hasMore: false, hasNewer: false, pending: false }
}

/** The same paging over a whole list (oldest first, each with an id), for the mock. */
export function pageOfTurns(all, page) {
  let end = all.length
  if (page.before) {
    const index = all.findIndex((t) => t.id >= page.before)
    end = index === -1 ? all.length : index
  }
  if (page.around) {
    const index = all.findIndex((t) => t.id === page.around)
    // An id that isn't there gets the newest window, like Jarvis.
    if (index !== -1) end = Math.min(all.length, index + Math.ceil(page.limit / 2))
  }
  const start = Math.max(0, end - page.limit)
  // hasNewer is only said for a window around a turn; scrolling up never needs it.
  return { turns: all.slice(start, end), hasMore: start > 0, hasNewer: Boolean(page.around) && end < all.length, pending: false }
}
