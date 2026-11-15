// Things Jarvis offers to do for Dylan (GET /offers on its local API): a
// short greeting for the time of day and up to three task cards, each with
// Start and Hide on the page (Dylan, 2026-11-14: "this is how proactive
// jarvis should be"). Jarvis writes snake_case; anything malformed is
// dropped, and nothing machine-looking reaches a card.

const MAX_OFFERS = 3
const MAX_TEXT = 400
// Ids, emails, key=value and long tokens don't belong on a card.
const MACHINE_BITS = /\w=\S|\S@\S+\.\w|[A-Za-z0-9_-]{24,}/

/** Trimmed text with no machine bits, or null. */
function words(value) {
  if (typeof value !== 'string') return null
  const trimmed = value.trim().slice(0, MAX_TEXT)
  if (trimmed === '' || MACHINE_BITS.test(trimmed)) return null
  return trimmed
}

/** One offer, or null when it lacks an id, title or what to say on Start. */
function parseOffer(raw) {
  const id = typeof raw?.id === 'string' && /^[\w-]{1,64}$/.test(raw.id) ? raw.id : null
  const title = words(raw?.title)
  const startText = typeof raw?.start_text === 'string' ? raw.start_text.trim().slice(0, MAX_TEXT) : ''
  if (id === null || title === null || startText === '') return null
  const created = typeof raw?.created === 'string' && !Number.isNaN(Date.parse(raw.created)) ? raw.created : null
  return { id, title, body: words(raw?.body) ?? '', startText, created }
}

/** Jarvis's answer as the page's shape, or null when it isn't one. */
export function parseOffers(raw) {
  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.offers)) return null
  const offers = []
  for (const item of raw.offers) {
    const offer = parseOffer(item)
    if (offer !== null) offers.push(offer)
  }
  return { greeting: words(raw.greeting), offers: offers.slice(0, MAX_OFFERS) }
}
