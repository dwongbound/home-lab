import type { ChatTurn } from '../types'

// When the phone leaves the page mid-reply (Safari's "Load failed"), the
// page loses the stream but Jarvis keeps working on the PC and saves his
// answer to the chat history (Dylan, 2026-11-13: "it should continue
// thinking and respond"). These pick his answer out of that history.

/** How long the page keeps checking for the answer after the stream dropped. */
export const CATCH_UP_MS = 15 * 60_000
/** How often it checks while the page is on screen. */
export const CATCH_UP_EVERY_MS = 4_000
// Clocks on the phone and the PC can differ a little; a question saved
// this long before it was sent still counts as the one we're waiting on.
const CLOCK_SLACK_MS = 2 * 60_000

/**
 * Jarvis's answer to `question`, asked at `askedAt` (ms), once it's in the
 * saved chat; null while he's still working. Only a question saved around
 * or after askedAt counts, so an older identical question doesn't answer it.
 */
export function findAnswer(lines: ChatTurn[], question: string, askedAt: number): string | null {
  const wanted = question.trim()
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i]
    if (line.role !== 'user' || line.text.trim() !== wanted) continue
    const at = Date.parse(line.at)
    // A line without a readable time can't be placed, so it can't be trusted either.
    if (Number.isNaN(at) || at < askedAt - CLOCK_SLACK_MS) return null
    const reply = lines[i + 1]
    if (reply && reply.role === 'jarvis' && reply.text.trim()) return reply.text
    return null
  }
  return null
}
