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
