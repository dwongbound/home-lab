// What Jarvis's approval requests are called on the page. Jarvis names the
// tool that wants to run (run_command, write_file, ...); the chat shows it
// in words.
import type { ApprovalBy, ApprovalOutcome } from '../types'

const TOOL_LABELS: Record<string, string> = {
  run_command: 'Run a command',
  run_windows: 'Run a Windows command',
  write_file: 'Write a file',
  edit_file: 'Edit a file',
  change_code: 'Change Jarvis’s code',
  apply_code_change: 'Put the new code live',
  change_setting: 'Change a setting',
}

/** The words for an approval's tool, e.g. "run_command" → "Run a command"; anything else → "Needs your OK". */
export function toolLabel(tool: string): string {
  return TOOL_LABELS[tool] ?? 'Needs your OK'
}

// Ids, calendar addresses and key=value pairs mean the summary is the raw
// tool call, not words (Dylan, 2026-11-13: "take out anything not human readable").
const MACHINE_BITS = /\w=\S|\S@\S+\.\w|[A-Za-z0-9_-]{20,}/

/**
 * The approval's summary as Dylan should read it. Jarvis writes them in
 * plain words; if a raw tool call slips through ("Google Calendar
 * delete_event (eventId=…)"), only the service and the action are kept:
 * "Google Calendar: delete event".
 */
export function readableSummary(summary: string): string {
  if (!MACHINE_BITS.test(summary)) return summary
  // The raw call is "<service words> <tool_name> <arguments…>": keep the
  // words before the tool name and the tool name itself, nothing after
  // (the arguments are where ids and names-in-pieces came from).
  const words = summary.split('(')[0].trim().split(/\s+/)
  const toolAt = words.findIndex((w) => w.includes('_'))
  if (toolAt === -1) return 'Jarvis wants to make a change. Ask him what it is before saying yes.'
  const service = words.slice(0, toolAt).filter((w) => !MACHINE_BITS.test(w)).join(' ')
  const action = words[toolAt].replace(/[^A-Za-z_]/g, '').replace(/_/g, ' ').trim()
  if (service) return `${service}: ${action}`
  return action
}

/** Which outcome an answer is: yes, no, or "wait" (held, not denied). */
export function settledAs(ok: boolean, later: boolean): ApprovalOutcome {
  if (ok) return 'approved'
  if (later) return 'later'
  return 'denied'
}

/**
 * A settled approval as one line in the conversation (Dylan, 2026-11-17: it
 * goes up into the history as a line, not a card): "Approved: …", "Denied
 * out loud: …", "Timed out: …", "Holding for later: …". The same words as
 * the app's ApprovalWording.settledLine (keep them in step).
 */
export function settledLine(a: { outcome?: ApprovalOutcome; by?: ApprovalBy; summary: string }): string {
  const what = readableSummary(a.summary)
  if (a.outcome === 'later') return `Holding for later: ${what}`
  if (a.by === 'timeout') return `Timed out: ${what}`
  const verb = a.outcome === 'approved' ? 'Approved' : 'Denied'
  if (a.by === 'telegram') return `${verb} on Telegram: ${what}`
  if (a.by === 'voice') return `${verb} out loud: ${what}`
  return `${verb}: ${what}`
}

/**
 * How long until an approval's `expires` time, in ms (0 once it has passed).
 * An unreadable or missing time gives null: it never times out here, and
 * Jarvis's own timeout still settles it.
 */
export function msUntilExpiry(expires: string, now: number = Date.now()): number | null {
  const at = Date.parse(expires)
  if (Number.isNaN(at)) return null
  return Math.max(0, at - now)
}
