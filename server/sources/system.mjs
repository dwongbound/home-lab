// Who is using the PC's memory and disks right now, for the apps' Memory and
// Storage panels beside the graphics card ring (Dylan, 2026-11-21). The page
// runs in a container and can't see the PC's programs, so Jarvis measures and
// answers GET /system; this file checks his answer and renames it. Whatever
// is used but unnamed becomes one "Everything else" row, as on the card.

const MAX_USERS = 12
const MAX_DISKS = 6
/** Below this, the unnamed leftover is measurement noise and gets no row. */
const OTHER_MIN_MB = 100
const OTHER_MIN_GB = 1
const ID = /^[\w-]{1,24}$/

/** A finite number above zero rounded to `places` decimals, or null. */
function amount(value, places) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return null
  const scale = 10 ** places
  return Math.round(value * scale) / scale
}

/** A trimmed string no longer than max, or null when it isn't one or is empty. */
function words(value, max) {
  if (typeof value !== 'string') return null
  return value.trim().slice(0, max) || null
}

/**
 * Named rows, biggest first, trimmed so they never add up to more than
 * `used`, plus one row for the unnamed rest when it's worth showing.
 * `size` is the key holding each row's amount ("mb" or "gb").
 */
function fitRows(rows, used, size, otherMin, other) {
  const sorted = [...rows].sort((a, b) => b[size] - a[size])
  let named = 0
  for (const row of sorted) {
    row[size] = Math.min(row[size], Math.max(0, used - named))
    named += row[size]
  }
  const kept = sorted.filter((row) => row[size] > 0)
  const rest = Math.round((used - named) * 10) / 10
  if (rest >= otherMin) kept.push({ ...other, [size]: rest })
  return kept
}

/** Jarvis's memory figures as the page's, or null when the totals aren't numbers. */
export function parseRam(raw) {
  const totalMb = amount(raw?.total_mb, 0)
  const usedMb = amount(raw?.used_mb, 0)
  if (totalMb === null || usedMb === null) return null
  const rows = []
  const list = Array.isArray(raw.users) ? raw.users.slice(0, MAX_USERS) : []
  for (const user of list) {
    const name = words(user?.name, 40)
    const mb = amount(user?.mb, 0)
    if (name === null || mb === null) continue
    rows.push({ name, role: words(user.role, 60) ?? '', mb })
  }
  // "pc" = the whole computer (Windows and Linux together), "linux" = only the Linux side Jarvis lives in.
  let scope = 'linux'
  if (raw.scope === 'pc') scope = 'pc'
  const used = Math.min(usedMb, totalMb)
  return { totalMb, usedMb: used, scope, users: fitRows(rows, used, 'mb', OTHER_MIN_MB, { name: 'Everything else', role: 'Other programs' }) }
}

/** One disk with its big folders, or null when it lacks an id, a name or its totals. */
function parseDisk(raw) {
  const id = typeof raw?.id === 'string' && ID.test(raw.id) ? raw.id : null
  const name = words(raw?.name, 40)
  const totalGb = amount(raw?.total_gb, 1)
  const usedGb = amount(raw?.used_gb, 1)
  if (id === null || name === null || totalGb === null || usedGb === null) return null
  const rows = []
  const list = Array.isArray(raw.users) ? raw.users.slice(0, MAX_USERS) : []
  for (const user of list) {
    const folder = words(user?.name, 40)
    const gb = amount(user?.gb, 1)
    if (folder === null || gb === null) continue
    rows.push({ name: folder, gb })
  }
  const used = Math.min(usedGb, totalGb)
  return { id, name, usedGb: used, totalGb, users: fitRows(rows, used, 'gb', OTHER_MIN_GB, { name: 'Everything else' }) }
}

/** Jarvis's disks as the page's list, or null when it isn't a list or none is usable. */
export function parseDisks(raw) {
  if (!Array.isArray(raw)) return null
  const disks = raw.slice(0, MAX_DISKS).map(parseDisk).filter((disk) => disk !== null)
  if (disks.length === 0) return null
  return disks
}

/** Jarvis's GET /system answer as {ram, disks}; each is null when he doesn't give it. */
export function parseSystem(raw) {
  return { ram: parseRam(raw?.ram), disks: parseDisks(raw?.disks) }
}
