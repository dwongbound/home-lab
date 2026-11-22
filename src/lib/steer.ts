// Messages sent while Jarvis is still answering (Dylan, 2026-11-21: "i should
// be able to send more than one message even while claude is thinking (and it
// should steer it)"). The page shows each one at once under the question
// being answered, above the reply that's still coming. If Jarvis says it came
// too late to steer, it moves out into a turn of its own that gets its own reply.

/** The bits of a chat turn these helpers look at. */
export interface SteerTurn { id: number; followUps?: string[] }

/** Adds a message sent mid-reply under the turn being answered. */
export function addFollowUp<T extends SteerTurn>(turns: T[], turnId: number, text: string): T[] {
  return turns.map((t) => (t.id === turnId ? { ...t, followUps: [...(t.followUps ?? []), text] } : t))
}

/** Takes one message back out from under a turn (the first match only, in case he sent the same words twice). */
export function dropFollowUp<T extends SteerTurn>(turns: T[], turnId: number, text: string): T[] {
  return turns.map((t) => {
    if (t.id !== turnId || !t.followUps) return t
    const at = t.followUps.indexOf(text)
    if (at === -1) return t
    const followUps = t.followUps.filter((_, i) => i !== at)
    return { ...t, followUps }
  })
}
