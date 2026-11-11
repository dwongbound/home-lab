// Categories Dylan picks on the Money page for purchases Copilot left in
// "Other" or with none. Copilot's connector is read-only, so the page can't
// change Copilot itself: it keeps the picks here until he applies them all
// in Copilot in one sitting, then marks them done.
//
// Kept on the PC (a JSON file on jarvis, money-picks-file.mjs), not in the
// browser, so the iPad, phone and Mac all see the same list. Without a
// file (the mock source, which also runs in the browser preview, and
// tests) they live in memory. This file has no Node imports for that reason.
//
// The file looks like:
//   { "picks": [{ "id", "category", "merchant", "date", "amount", "pickedAt" }],
//     "remindAt": "2026-11-11T04:00:00.000Z" | null }
// Same rule as needsCategory in src/lib/money.ts: these mean "not sorted yet".
const UNSORTED = new Set(['', 'other', 'uncategorized', 'uncategorised'])
const MAX_PICKS = 500
const MAX_TEXT = 120

/** An empty list with no reminder. */
function emptyState() {
  return { picks: [], remindAt: null }
}

/** Trims a string and caps its length; anything else becomes ''. */
function cleanString(value) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, MAX_TEXT)
}

/** True for a string the Date parser understands. */
function isDate(value) {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value))
}

/** One pick from the file, or null when it's broken (so one bad line can't sink the rest). */
function readPick(raw) {
  if (raw === null || typeof raw !== 'object') return null
  const id = cleanString(raw.id)
  const category = cleanString(raw.category)
  if (!id || !category || typeof raw.amount !== 'number') return null
  return {
    id,
    category,
    merchant: cleanString(raw.merchant),
    date: isDate(raw.date) ? raw.date : '',
    amount: raw.amount,
    pickedAt: isDate(raw.pickedAt) ? raw.pickedAt : new Date(0).toISOString(),
  }
}

/**
 * Creates the store. `storage` ({load, save}) is where the picks are kept;
 * null keeps them in memory. `now` is injectable so tests can pin the clock.
 * @param {{ storage?: { load(): Promise<any>, save(state: any): Promise<void> } | null, now?: () => Date }} [options]
 */
export function createPickStore({ storage = null, now = () => new Date() } = {}) {
  let state = emptyState()
  let loaded = storage === null
  // Changes run one after another, so two quick taps can't lose a pick.
  let queue = Promise.resolve()

  /** Reads the saved list once. A missing or broken one starts empty. */
  async function load() {
    if (loaded) return
    loaded = true
    try {
      const parsed = await storage.load()
      const picks = Array.isArray(parsed?.picks) ? parsed.picks.map(readPick).filter(Boolean) : []
      state = { picks, remindAt: isDate(parsed?.remindAt) ? parsed.remindAt : null }
    } catch {
      state = emptyState()
    }
  }

  /** Saves the whole list, when there's somewhere to save it. */
  async function save() {
    if (storage === null) return
    await storage.save(state)
  }

  /**
   * Runs one change after any before it has finished.
   * @template T
   * @param {() => Promise<T>} fn
   * @returns {Promise<T>}
   */
  function serial(fn) {
    const run = queue.then(fn, fn)
    queue = run.catch(() => {})
    return run
  }

  /** Copies of the picks and reminder, for the snapshot. */
  function view() {
    return { picks: state.picks.map((p) => ({ ...p })), remindAt: state.remindAt }
  }

  /** Saves or replaces the category for one purchase. */
  function pick(body) {
    const id = cleanString(body.id)
    const category = cleanString(body.category)
    if (!id || !category) return { ok: false, message: 'Send an id and a category' }
    if (typeof body.amount !== 'number' || !Number.isFinite(body.amount)) return { ok: false, message: 'Send the amount' }
    const others = state.picks.filter((p) => p.id !== id)
    if (others.length >= MAX_PICKS) return { ok: false, message: 'That is a lot of picks: apply some in Copilot first' }
    const entry = {
      id,
      category,
      merchant: cleanString(body.merchant),
      date: isDate(body.date) ? body.date : '',
      amount: body.amount,
      pickedAt: now().toISOString(),
    }
    state.picks = [...others, entry]
    // The first pick sets the reminder the page suggested; later ones keep it.
    if (state.remindAt === null && isDate(body.remindAt)) state.remindAt = body.remindAt
    return { ok: true, message: `Saved: ${category}` }
  }

  /** Forgets the picks for these purchases (done in Copilot, or picked by mistake). */
  function clear(body) {
    if (!Array.isArray(body.ids)) return { ok: false, message: 'Send the ids to clear' }
    const gone = new Set(body.ids.filter((x) => typeof x === 'string'))
    const before = state.picks.length
    state.picks = state.picks.filter((p) => !gone.has(p.id))
    if (state.picks.length === 0) state.remindAt = null
    const cleared = before - state.picks.length
    let message = `Cleared ${cleared}`
    if (cleared === 1) message = 'Cleared 1'
    return { ok: true, message }
  }

  /** Moves the reminder. */
  function remind(body) {
    if (!isDate(body.at)) return { ok: false, message: 'Send a time to remind you at' }
    if (state.picks.length === 0) return { ok: false, message: 'Nothing to remind you about' }
    state.remindAt = new Date(body.at).toISOString()
    return { ok: true, message: 'Reminder moved' }
  }

  return {
    /**
     * The picks for the snapshot. Purchases the digest now shows with a real
     * category were sorted in Copilot, so they drop off by themselves.
     */
    async read(recent = []) {
      return serial(async () => {
        await load()
        const sorted = new Set()
        for (const t of recent) {
          if (UNSORTED.has(String(t.category ?? '').trim().toLowerCase())) continue
          sorted.add(t.id)
        }
        const kept = state.picks.filter((p) => !sorted.has(p.id))
        if (kept.length !== state.picks.length) {
          state.picks = kept
          if (kept.length === 0) state.remindAt = null
          await save()
        }
        return view()
      })
    },

    /** One change: {op: 'pick' | 'clear' | 'remind', ...}. */
    async change(body) {
      return serial(async () => {
        await load()
        let result = { ok: false, message: 'Unknown change' }
        if (body?.op === 'pick') result = pick(body)
        if (body?.op === 'clear') result = clear(body)
        if (body?.op === 'remind') result = remind(body)
        if (result.ok) await save()
        return result
      })
    },
  }
}
