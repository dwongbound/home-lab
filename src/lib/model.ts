// Which brain answered a chat turn (Dylan, 2026-11-16): Claude most of the
// time, Ornith (the local model) when Claude's plan is out of room. Jarvis
// names the model with each reply; the chat shows it as a small chip over
// the reply, orange for Claude and blue for anything local.

/** The chip's text for a model name from Jarvis: "claude" → "Claude", "ornith" → "Ornith". */
export function modelLabel(model: string): string {
  const name = model.trim()
  if (!name) return ''
  return name[0].toUpperCase() + name.slice(1)
}

/** The chip's colour family: Claude is orange, every local model is blue. */
export function modelTone(model: string): 'claude' | 'local' {
  return model.trim().toLowerCase() === 'claude' ? 'claude' : 'local'
}
