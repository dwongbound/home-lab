// Reports (Dylan, 2026-11-18): when a long task ends in more than a chat
// reply can hold, Jarvis writes one self-contained HTML page and keeps it
// on the PC (GET /reports, GET /reports/{id}). He deletes a report 30 days
// after it was made unless Keep is on, and keeps them all under a size cap.
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

/** One report from Jarvis in the page's shape; null when it isn't one. */
export function parseReport(raw) {
  if (!isReportId(raw?.id)) return null
  const title = text(raw.title, 200)
  const created = time(raw.created)
  if (!title || created === null) return null
  const kept = raw.kept === true
  let expires = null
  // A kept report has no end date, whatever Jarvis sent with it.
  if (!kept) expires = time(raw.expires)
  return { id: raw.id, title, summary: text(raw.summary, 500), created, expires, kept, bytes: bytes(raw.bytes) }
}

/**
 * Everything the Reports panel needs from Jarvis's GET /reports: the
 * reports newest first, how much room they take, and the rules (days kept,
 * the size cap). Null when the answer isn't the expected shape.
 */
export function parseReports(body) {
  if (!Array.isArray(body?.reports)) return null
  const reports = body.reports.map(parseReport).filter((r) => r !== null).slice(0, MAX_REPORTS)
  let keepDays = 30
  if (typeof body.keep_days === 'number' && body.keep_days > 0) keepDays = Math.round(body.keep_days)
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
<p class="dim">Reports are deleted 30 days after they are made unless Keep is on.</p>
</body>
</html>
`
}
