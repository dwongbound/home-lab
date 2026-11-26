// What Jarvis's own background jobs have spent on Claude, for the apps'
// Claude section: a ring of today's spend against his daily budget and a
// bar for each of the last seven days (Dylan, 2026-11-26). Jarvis counts it
// and answers GET /claude/usage; this file checks his answer and renames it.
// Dollars are at API prices; chat and Talk turns aren't counted.

const MAX_KINDS = 20
const MAX_DAYS = 7
const DAY = /^\d{4}-\d{2}-\d{2}$/
const LEVELS = ['ok', 'slow', 'held']

/** A finite number of zero or more rounded to cents, or null. */
function dollars(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null
  return Math.round(value * 100) / 100
}

/**
 * Jarvis's usage as the apps': `{dailyUsd, spentUsd, level, today, days}`.
 * `today` is spend by kind of job, biggest first; `days` is oldest first.
 * Null when the budget or today's spend isn't a number (an older Jarvis).
 */
export function parseClaudeUsage(raw) {
  const dailyUsd = dollars(raw?.daily_usd)
  const spentUsd = dollars(raw?.spent_usd)
  if (dailyUsd === null || spentUsd === null) return null
  // "slow" = he's close to the budget and holding back, "held" = background work has stopped for today.
  let level = 'ok'
  if (LEVELS.includes(raw.level)) level = raw.level
  const today = []
  for (const row of Array.isArray(raw.today) ? raw.today.slice(0, MAX_KINDS) : []) {
    const usd = dollars(row?.usd)
    if (typeof row?.kind !== 'string' || row.kind.trim() === '' || usd === null) continue
    let calls = 0
    if (typeof row.calls === 'number' && Number.isFinite(row.calls) && row.calls > 0) calls = Math.floor(row.calls)
    today.push({ kind: row.kind.trim().slice(0, 40), usd, calls })
  }
  today.sort((a, b) => b.usd - a.usd)
  const days = []
  for (const row of Array.isArray(raw.days) ? raw.days : []) {
    const usd = dollars(row?.usd)
    if (typeof row?.date !== 'string' || !DAY.test(row.date) || usd === null) continue
    days.push({ date: row.date, usd })
  }
  days.sort((a, b) => a.date.localeCompare(b.date))
  return { dailyUsd, spentUsd, level, today, days: days.slice(-MAX_DAYS) }
}
