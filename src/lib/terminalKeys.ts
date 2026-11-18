// Keys and clipboard for the terminal on Services. The terminal is ttyd in
// an iframe on the same origin (/shell/), and ttyd puts its xterm.js
// Terminal on window.term, so the page can type into it and read its
// screen. An iPhone keyboard has no Ctrl, Esc, Tab or arrows, and
// long-press selection inside xterm is unreliable, so these buttons are the
// way in and out on a phone.

/** The bits of ttyd's xterm.js Terminal that the key bar uses. */
export type TermLike = {
  /** Types data as if from the keyboard (xterm 5.4+). */
  input?: (data: string, wasUserInput?: boolean) => void
  /** Pastes text (bracketed when the program asked for it). */
  paste: (text: string) => void
  focus: () => void
  getSelection: () => string
  hasSelection: () => boolean
  rows: number
  buffer: { active: { viewportY: number; length: number; getLine: (y: number) => { translateToString: (trim?: boolean) => string } | undefined } }
  /** Older xterm: the internal path to the same keyboard event. */
  _core?: { coreService?: { triggerDataEvent: (data: string, wasUserInput?: boolean) => void } }
}

/** One key on the bar: what it says, what a screen reader hears, and what it sends. */
export type TermKey = { label: string; name: string; data: string }

// Ctrl+C first, since it's the one he asked for; the rest cover what the iPhone keyboard lacks.
export const TERM_KEYS: TermKey[] = [
  { label: 'Ctrl+C', name: 'Send Ctrl+C', data: '\x03' },
  { label: 'Esc', name: 'Send Escape', data: '\x1b' },
  { label: 'Tab', name: 'Send Tab', data: '\t' },
  { label: '↑', name: 'Send up arrow', data: '\x1b[A' },
  { label: '↓', name: 'Send down arrow', data: '\x1b[B' },
  { label: 'Ctrl+D', name: 'Send Ctrl+D', data: '\x04' },
]

/** ttyd's Terminal inside the frame, or null while it loads or when the shell is off. */
export function findTerm(frame: HTMLIFrameElement | null): TermLike | null {
  try {
    const win = frame?.contentWindow as (Window & { term?: TermLike }) | null | undefined
    const term = win?.term
    if (term && typeof term.paste === 'function') return term
    return null
  } catch {
    // A cross-origin frame (never expected here) throws on access.
    return null
  }
}

/**
 * Sends key bytes as typed input. paste() can't be used for these: with
 * bracketed paste on, a pasted Ctrl+C arrives as text, not as an interrupt.
 */
export function sendKey(term: TermLike, data: string): void {
  if (typeof term.input === 'function') {
    term.input(data, true)
    return
  }
  term._core?.coreService?.triggerDataEvent(data, true)
}

/** The selected text, or else every line on screen with trailing blank lines dropped. */
export function terminalText(term: TermLike): string {
  if (term.hasSelection()) return term.getSelection()
  const buf = term.buffer.active
  const lines: string[] = []
  const end = Math.min(buf.viewportY + term.rows, buf.length)
  for (let y = buf.viewportY; y < end; y++) {
    lines.push(buf.getLine(y)?.translateToString(true) ?? '')
  }
  while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop()
  return lines.join('\n')
}
