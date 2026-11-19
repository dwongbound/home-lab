import type { JarvisReport, JarvisReports, ReportChange } from '../types'

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

/** The lengths of time a report can be kept, shortest first; null = for good. */
export const KEEP_CHOICES: (14 | 30 | 90 | null)[] = [14, 30, 90, null]

/** A number of days in everyday words: "2 weeks", "1 month", "3 months", else "45 days". */
function daysText(days: number): string {
  if (days === 14) return '2 weeks'
  if (days === 30) return '1 month'
  if (days === 90) return '3 months'
  return `${days} days`
}

/** The words on a report's keep button and its choices: "Keep 2 weeks", "Keep forever". */
export function keepLabel(days: number | null): string {
  if (days === null) return 'Keep forever'
  return `Keep ${daysText(days)}`
}

/** The change to send for one keep choice. */
export function keepChange(id: string, days: 14 | 30 | 90 | null): ReportChange {
  if (days === null) return { op: 'keep', id, keep: true }
  return { op: 'keep', id, days }
}

/** When Jarvis deletes a report: "Kept until you change it", "Deletes today", "Deletes tomorrow" or "Deletes Dec 18". */
export function endText(report: JarvisReport, now: Date): string {
  if (report.kept || report.expires === null) return 'Kept until you change it'
  const left = Date.parse(report.expires) - now.getTime()
  if (left < DAY_MS) return 'Deletes today'
  if (left < 2 * DAY_MS) return 'Deletes tomorrow'
  const day = new Date(report.expires).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: TIME_ZONE })
  return `Deletes ${day}`
}

/** The rule and the room used, in one line under the panel title. */
export function rulesText(reports: JarvisReports): string {
  const rule = `Each report is kept ${daysText(reports.keepDays)} unless you pick longer for it.`
  if (reports.reports.length === 0) return rule
  let room = `Using ${sizeText(reports.totalBytes)}`
  if (reports.maxBytes > 0) room += ` of ${sizeText(reports.maxBytes)}`
  return `${rule} ${room}.`
}
