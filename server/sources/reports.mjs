// Reports (Dylan, 2026-11-18): when a long task ends in more than a chat
// reply can hold, Jarvis writes one self-contained HTML page and keeps it
// on the PC (GET /reports, GET /reports/{id}). He keeps a report 2 weeks
// unless Dylan picks longer for it (1 month, 3 months, or for good;
// 2026-11-19), and keeps them all under a size cap.
// This file cleans his list for the page, and wraps a report's HTML in
// headers that stop it running scripts or loading anything from outside.

const MAX_REPORTS = 100
/** Report ids are short hex or word-like strings; anything else never reaches Jarvis. */
const REPORT_ID = /^[A-Za-z0-9_-]{1,80}$/

/**
 * What a report page is allowed to do: show its own inline styles and
 * inline (data:) pictures, and nothing else. `sandbox` gives it an origin of
 * its own, so even a script that slipped past Jarvis's cleaning couldn't
 * run, and nothing in it can call this page's API.
 */
export const REPORT_CSP = [
  "default-src 'none'",
  "style-src 'unsafe-inline'",
  'img-src data:',
  'font-src data:',
  "base-uri 'none'",
  "form-action 'none'",
  'sandbox allow-popups allow-popups-to-escape-sandbox',
].join('; ')

/** How long one report can be kept, in days, besides "for good". */
export const KEEP_DAYS = [14, 30, 90]
const DEFAULT_KEEP_DAYS = 14

/**
 * What a keep request asks for, from its body: {days: 14 | 30 | 90}, or
 * {keep: true} (for good) or {keep: false} (back to 2 weeks). Null when it's none of those.
 */
export function parseKeepChoice(body) {
  if (KEEP_DAYS.includes(body?.days)) return { days: body.days }
  if (typeof body?.keep === 'boolean') return { keep: body.keep }
  return null
}

/** True when an id is safe to put in a path to Jarvis. */
export function isReportId(id) {
  return typeof id === 'string' && REPORT_ID.test(id)
}

/** A trimmed string no longer than max, or '' when it isn't a string. */
function text(value, max) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, max)
}

/** An ISO time the browser can parse, or null. */
function time(value) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return null
  return value
}

/** A whole number of bytes, zero or more; 0 when it isn't a number. */
function bytes(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return 0
  return Math.round(value)
}

/**
 * One report from Jarvis in the page's shape; null when it isn't one.
 * `usualDays` is how long a report is kept when Jarvis doesn't say for this one.
 */
export function parseReport(raw, usualDays = DEFAULT_KEEP_DAYS) {
  if (!isReportId(raw?.id)) return null
  const title = text(raw.title, 200)
  const created = time(raw.created)
  if (!title || created === null) return null
  const kept = raw.kept === true
  let expires = null
  // A kept report has no end date, whatever Jarvis sent with it.
  if (!kept) expires = time(raw.expires)
  // How many days it's kept for; null when it's kept for good.
  let keepDays = null
  if (!kept) keepDays = usualDays
  if (!kept && typeof raw.keep_days === 'number' && raw.keep_days > 0) keepDays = Math.round(raw.keep_days)
  return { id: raw.id, title, summary: text(raw.summary, 500), created, expires, kept, keepDays, bytes: bytes(raw.bytes) }
}

/**
 * Everything the Reports panel needs from Jarvis's GET /reports: the
 * reports newest first, how much room they take, and the rules (days kept,
 * the size cap). Null when the answer isn't the expected shape.
 */
export function parseReports(body) {
  if (!Array.isArray(body?.reports)) return null
  let keepDays = DEFAULT_KEEP_DAYS
  if (typeof body.keep_days === 'number' && body.keep_days > 0) keepDays = Math.round(body.keep_days)
  const reports = body.reports.map((raw) => parseReport(raw, keepDays)).filter((r) => r !== null).slice(0, MAX_REPORTS)
  return { reports, totalBytes: bytes(body.total_bytes), keepDays, maxBytes: bytes(body.max_bytes) }
}

/** The small page shown in place of a report that's gone or can't be fetched. */
export function missingReportPage(message) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Report not available</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; margin: 0; padding: 48px 20px; background: #14161c; color: #e9e6df; text-align: center; }
  p { max-width: 32rem; margin: 0 auto 12px; }
  .dim { color: #a6a299; }
</style>
</head>
<body>
<p>${message}</p>
<p class="dim">Reports are kept 2 weeks unless you pick longer for one.</p>
</body>
</html>
`
}
