// Today's calories from Jarvis (GET /nutrition/today on its local API), for
// the Watch's "Calories left" complication (Dylan, 2026-11-18). Numbers only,
// never meal names. Jarvis writes snake_case; anything malformed gives null.

/** A whole number of at least `min`, or null. */
function whole(value, min) {
  if (Number.isInteger(value) && value >= min) return value
  return null
}

/** Jarvis's answer as the page's shape, or null when the date, eaten or goal is missing. */
export function parseNutrition(raw) {
  if (!raw || typeof raw !== 'object') return null
  const eaten = whole(raw.eaten, 0)
  const goal = whole(raw.goal, 1)
  if (typeof raw.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(raw.date) || eaten === null || goal === null) return null
  return {
    date: raw.date,
    eaten,
    goal,
    // Worked out here so it can't disagree with the two numbers beside it; negative when he's over.
    left: goal - eaten,
    burned: whole(raw.burned, 0),
    protein: whole(raw.protein, 0),
    proteinGoal: whole(raw.protein_goal, 1),
  }
}

// The Diet screen in the apps (Dylan, 2026-11-18) reads one day in full
// (GET /nutrition/day) and a week of totals for its day strip
// (GET /nutrition/week). These carry meal names, so unlike today's numbers
// they're never in the snapshot: only the signed-in caller asks for them.

const DAY = /^\d{4}-\d{2}-\d{2}$/
const MAX_ITEMS = 100

/** True for a calendar day written "2026-11-18". */
export function isDay(value) {
  return typeof value === 'string' && DAY.test(value)
}

/** A number of zero or more, rounded to one decimal (grams come in tenths), or null. */
function amount(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null
  return Math.round(value * 10) / 10
}

/** Calories, protein, fat and carbs from one of Jarvis's objects; null where he has none. */
function macros(raw) {
  return { calories: amount(raw?.calories), protein: amount(raw?.protein), fat: amount(raw?.fat), carbs: amount(raw?.carbs) }
}

/** A trimmed string no longer than max, or null when it isn't one or is empty. */
function words(value, max) {
  if (typeof value !== 'string') return null
  return value.trim().slice(0, max) || null
}

/** One thing he ate, or null when it has no id, name or time. */
function parseItem(raw) {
  const id = words(typeof raw?.id === 'number' ? String(raw.id) : raw?.id, 80)
  const name = words(raw?.name, 200)
  if (id === null || name === null || typeof raw.at !== 'string' || Number.isNaN(Date.parse(raw.at))) return null
  return { id, at: raw.at, name, portion: words(raw.portion, 80), ...macros(raw), hasPhoto: raw.has_photo === true }
}

/** One day of the meal log in the page's shape (items in time order), or null when it isn't one. */
export function parseNutritionDay(raw) {
  if (!isDay(raw?.date) || !Array.isArray(raw.items)) return null
  const items = raw.items.map(parseItem).filter((item) => item !== null).slice(0, MAX_ITEMS)
  items.sort((a, b) => Date.parse(a.at) - Date.parse(b.at))
  return { date: raw.date, goals: macros(raw.goals), totals: { ...macros(raw.totals), burned: amount(raw.totals?.burned) }, items }
}

/** A week of calories and protein eaten against their goals, one row per day, or null when it isn't one. */
export function parseNutritionWeek(raw) {
  if (!isDay(raw?.start) || !Array.isArray(raw.days)) return null
  const days = raw.days
    .filter((day) => isDay(day?.date))
    .slice(0, 7)
    .map((day) => ({ date: day.date, calories: amount(day.calories), goal: amount(day.goal), protein: amount(day.protein), proteinGoal: amount(day.protein_goal) }))
  return { start: raw.start, days }
}

// The Diet screen's food list scrolls back into the past (Dylan, 2026-11-19),
// so it asks for a run of days at a time (GET /nutrition/days) instead of one.
export const MAX_DAYS = 14
const DEFAULT_DAYS = 7

/** How many days to send for a `count` from the address: 7 when it's missing, 1 to 14, or null when it isn't a whole number. */
export function dayCount(value) {
  if (value === null || value === '') return DEFAULT_DAYS
  if (!/^\d{1,3}$/.test(value)) return null
  return Math.min(MAX_DAYS, Math.max(1, Number(value)))
}

/**
 * A run of days of the meal log, newest first, each like parseNutritionDay's,
 * plus the earliest day with anything logged (where the list ends); null when it isn't one.
 */
export function parseNutritionDays(raw) {
  if (!Array.isArray(raw?.days)) return null
  const days = raw.days.map(parseNutritionDay).filter((day) => day !== null).slice(0, MAX_DAYS)
  days.sort((a, b) => b.date.localeCompare(a.date))
  return { days, earliest: isDay(raw.earliest) ? raw.earliest : null }
}

// A meal's photo (Dylan, 2026-11-19): the food list shows a small thumbnail,
// and the full picture only on a tap.
const MEAL_ID = /^[\w-]{1,80}$/
const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic']

/** True for an id a meal can have (what the day's items carry). */
export function isMealId(value) {
  return typeof value === 'string' && MEAL_ID.test(value)
}

/** The picture kind Jarvis named, or JPEG when it isn't one of the kinds the apps can show. */
export function photoType(value) {
  const type = typeof value === 'string' ? value.split(';')[0].trim().toLowerCase() : ''
  return PHOTO_TYPES.includes(type) ? type : 'image/jpeg'
}
