import type { JarvisReport, JarvisReports } from '../types'

// Words for the Reports panel: how big a report is, when Jarvis deletes it,
// and the one line that says how long reports are kept and how much room
// they take. Dylan asked for this to be plain (2026-11-18): he should never
// have to wonder whether a report is still there or filling the disk.

const DAY_MS = 86_400_000
/** Dates are shown the way the PC and Dylan see them. */
const TIME_ZONE = 'America/Los_Angeles'

/** A size in plain units: "850 bytes", "184 KB", "1.2 MB". */
export function sizeText(bytes: number): string {
  if (bytes < 1000) return `${bytes} bytes`
  if (bytes < 1_000_000) return `${Math.round(bytes / 1000)} KB`
  return `${Math.round(bytes / 100_000) / 10} MB`
}

/** Where a report's own page lives. */
export function reportHref(id: string): string {
  return `/reports/${encodeURIComponent(id)}`
}

/** When Jarvis deletes a report: "Kept", "Deletes today", "Deletes tomorrow" or "Deletes Dec 18". */
export function endText(report: JarvisReport, now: Date): string {
  if (report.kept || report.expires === null) return 'Kept until you switch Keep off'
  const left = Date.parse(report.expires) - now.getTime()
  if (left < DAY_MS) return 'Deletes today'
  if (left < 2 * DAY_MS) return 'Deletes tomorrow'
  const day = new Date(report.expires).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: TIME_ZONE })
  return `Deletes ${day}`
}

/** The rule and the room used, in one line under the panel title. */
export function rulesText(reports: JarvisReports): string {
  const rule = `Each report is deleted ${reports.keepDays} days after it was made, unless Keep is on.`
  if (reports.reports.length === 0) return rule
  let room = `Using ${sizeText(reports.totalBytes)}`
  if (reports.maxBytes > 0) room += ` of ${sizeText(reports.maxBytes)}`
  return `${rule} ${room}.`
}
