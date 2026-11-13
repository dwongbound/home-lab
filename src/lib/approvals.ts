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

/** What a settled approval says: the answer, and who gave it if not this page. */
export function outcomeText(a: { outcome?: ApprovalOutcome; by?: ApprovalBy }): string {
  if (a.outcome === 'later') return 'Holding this for later. Say “go ahead” when you’re ready.'
  if (a.by === 'timeout') return 'No answer in time, so he left it alone'
  const verb = a.outcome === 'approved' ? 'Approved' : 'Denied'
  if (a.by === 'telegram') return `${verb} on Telegram`
  if (a.by === 'voice') return `${verb} out loud`
  return verb
}
