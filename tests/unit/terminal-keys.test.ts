import { describe, expect, it, vi } from 'vitest'
import { TERM_KEYS, findTerm, sendKey, terminalText, type TermLike } from '../../src/lib/terminalKeys'

/** A stand-in for ttyd's xterm Terminal with the given screen lines. */
function fakeTerm(lines: string[], opts: { selection?: string; input?: boolean; rows?: number; viewportY?: number } = {}): TermLike & { sent: string[] } {
  const sent: string[] = []
  const term: TermLike & { sent: string[] } = {
    sent,
    paste: vi.fn(),
    focus: vi.fn(),
    getSelection: () => opts.selection ?? '',
    hasSelection: () => Boolean(opts.selection),
    rows: opts.rows ?? lines.length,
    buffer: { active: { viewportY: opts.viewportY ?? 0, length: lines.length, getLine: (y) => ({ translateToString: () => lines[y] }) } },
    _core: { coreService: { triggerDataEvent: (d) => { sent.push(`core:${d}`) } } },
  }
  if (opts.input !== false) term.input = (d) => { sent.push(d) }
  return term
}

describe('terminal keys', () => {
  it('Ctrl+C sends the interrupt byte and comes first', () => {
    expect(TERM_KEYS[0]).toMatchObject({ label: 'Ctrl+C', data: '\x03' })
  })

  it('sends keys as typed input, not as a paste', () => {
    const term = fakeTerm([])
    sendKey(term, '\x03')
    expect(term.sent).toEqual(['\x03'])
    expect(term.paste).not.toHaveBeenCalled()
  })

  it('falls back to the core data event on an older xterm', () => {
    const term = fakeTerm([], { input: false })
    sendKey(term, '\x03')
    expect(term.sent).toEqual(['core:\x03'])
  })

  it('copies the selection when there is one', () => {
    expect(terminalText(fakeTerm(['a', 'b'], { selection: 'picked' }))).toBe('picked')
  })

  it('otherwise copies the visible screen, without trailing blank lines', () => {
    const term = fakeTerm(['old', '$ ls', 'file.txt', '', ''], { rows: 4, viewportY: 1 })
    expect(terminalText(term)).toBe('$ ls\nfile.txt')
  })

  it('finds no terminal while the frame is empty or missing', () => {
    expect(findTerm(null)).toBeNull()
    const frame = document.createElement('iframe')
    document.body.append(frame)
    expect(findTerm(frame)).toBeNull()
    frame.remove()
  })
})
