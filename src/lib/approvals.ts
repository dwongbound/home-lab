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

/** The words for an approval's tool, e.g. "run_command" → "Run a command"; anything else → "Do this". */
export function toolLabel(tool: string): string {
  return TOOL_LABELS[tool] ?? 'Do this'
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
