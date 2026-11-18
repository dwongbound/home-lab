// The note a work dot opens is wide enough that its words aren't cut off,
// grows with them, and past its cap scrolls inside itself.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const css = readFileSync(resolve(__dirname, '../../src/styles.css'), 'utf8')
const note = css.match(/\.orb > \.orb__note \{([^}]*)\}/)?.[1] ?? ''
const words = css.match(/\.orb__note-words \{([^}]*)\}/)?.[1] ?? ''

/** The px in a rule's `min(<px>px, ...)` value for a property, or 0. */
function px(rule: string, prop: string): number {
  return Number(rule.match(new RegExp(`(?:^|;)\\s*${prop}: min\\((\\d+)px`))?.[1] ?? 0)
}

describe('the orb\'s work note', () => {
  it('is wider than before and grows with its words', () => {
    expect(note).toMatch(/width: max-content/)
    expect(px(note, 'max-width')).toBeGreaterThan(300)
    expect(px(note, 'min-width')).toBeGreaterThan(0)
  })

  it('scrolls inside itself when the words still don\'t fit', () => {
    expect(px(note, 'max-height')).toBeGreaterThan(0)
    expect(note).toMatch(/overflow-y: auto/)
  })

  it('wraps long words rather than cutting them off', () => {
    expect(words).toMatch(/overflow-wrap: anywhere/)
  })
})
