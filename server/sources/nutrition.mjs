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

/** A week of calories eaten against the goal, one row per day, or null when it isn't one. */
export function parseNutritionWeek(raw) {
  if (!isDay(raw?.start) || !Array.isArray(raw.days)) return null
  const days = raw.days
    .filter((day) => isDay(day?.date))
    .slice(0, 7)
    .map((day) => ({ date: day.date, calories: amount(day.calories), goal: amount(day.goal) }))
  return { start: raw.start, days }
}
