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
