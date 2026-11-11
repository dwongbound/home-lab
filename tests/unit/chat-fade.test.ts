// The chat's words fade out at its top and bottom edges as they scroll,
// in the pop-up and on /talk, rather than being cut off hard.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const css = readFileSync(resolve(__dirname, '../../src/styles.css'), 'utf8')

describe('chat edges', () => {
  it('fade at the top and bottom in every chat, with room for the end lines to sit clear', () => {
    const rule = css.match(/\.dialog--chat \.chat__turns \{([^}]*)\}/)?.[1] ?? ''
    expect(rule).toMatch(/-webkit-mask-image: linear-gradient\(to bottom, transparent 0, #000 \d+px, #000 calc\(100% - \d+px\), transparent\)/)
    expect(rule).toMatch(/padding-top: \d+px/)
    expect(rule).toMatch(/padding-bottom: \d+px/)
  })
})
