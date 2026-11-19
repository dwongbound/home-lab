// Where the words Jarvis just heard belong in the chat (Dylan, 2026-11-16).
//
// Jarvis decides you're done, starts an answer, and you carry on talking.
// Since 2026-11-16 he joins the new words onto the question he was already
// answering and sends the transcript again with joined: true. The page
// keeps all of that in the one bubble, updating it in place, instead of
// starting a second bubble under a reply that never came.

/** The bits of a chat turn these helpers look at. */
export interface HeardTurn { id: number; question: string; answer: string; done: boolean }

/**
 * Whether the words can go into the open turn: Jarvis joined them onto his
 * current question and hasn't said anything back yet.
 */
export function canJoin<T extends HeardTurn>(turns: T[], openId: number, joined: boolean): boolean {
  if (!joined) return false
  const open = turns.find((t) => t.id === openId)
  return open !== undefined && open.answer === '' && !open.done
}

/** Rewrites the open turn's question with the joined words. */
export function joinHeard<T extends HeardTurn>(turns: T[], openId: number, question: string): T[] {
  return turns.map((t) => (t.id === openId ? { ...t, question, done: false } : t))
}

// Live words that hold still (Dylan, 2026-11-19: "a lot of rewriting my
// dialogue"). Each partial now says how many of its leading words are
// settled: Jarvis won't change those again. Only the tail after them is
// still a guess, and the page shows that part lighter.

/** The live words in two parts: what's settled and the tail that may still change. */
export interface HeardParts { settled: string; tentative: string }

/**
 * Splits the live words after their first `stable` words. An older Jarvis
 * sends no count (null): then every word may still change.
 */
export function splitHeard(text: string, stable: number | null): HeardParts {
  if (stable === null || stable <= 0) return { settled: '', tentative: text }
  const words = text.split(/\s+/).filter((word) => word !== '')
  if (stable >= words.length) return { settled: text, tentative: '' }
  // The space between the two parts goes with the tail, so the settled part never shifts.
  return { settled: words.slice(0, stable).join(' '), tentative: ` ${words.slice(stable).join(' ')}` }
}

/**
 * What to show once the turn is over. When Jarvis says the final is the
 * same as the live words (only punctuation or capitals differ), the words
 * already on screen stay exactly as they are; otherwise the final replaces them.
 */
export function settledQuestion(shown: string, final: string, same: boolean): string {
  if (same && shown.trim() !== '') return shown
  return final
}
