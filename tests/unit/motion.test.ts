// Motion must degrade to the plain page: every animation in the stylesheet
// sits inside the prefers-reduced-motion: no-preference block, so with
// reduced motion (or no animation support) everything is simply there.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const css = readFileSync(resolve(__dirname, '../../src/styles.css'), 'utf8')

/** The text of the `@media (prefers-reduced-motion: no-preference)` block. */
function motionBlock(source: string): string {
  const start = source.indexOf('@media (prefers-reduced-motion: no-preference)')
  let depth = 0
  for (let i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] === '{') depth++
    if (source[i] === '}') depth--
    if (depth === 0) return source.slice(start, i + 1)
  }
  return ''
}

describe('motion', () => {
  it('only animates inside the no-preference block', () => {
    const block = motionBlock(css)
    expect(block).not.toBe('')
    const outside = css.replace(block, '')
    expect(outside).not.toMatch(/\banimation\s*:/)
  })

  it('reveals what is inside glass panels on scroll, never the glass itself', () => {
    const block = motionBlock(css)
    // Fading a glass panel, or anything holding one, breaks its blur.
    expect(block).toMatch(/\.main \.glass > \*\s*\{[^}]*animation-timeline:\s*view\(\)/)
    // The one animation glass may run is the landing's frost, which never
    // touches opacity or transform (checked below).
    const glassAnimations = [...block.matchAll(/\.glass\s*\{([^}]*)\}/g)].map((m) => m[1]).filter((rule) => /animation/.test(rule))
    for (const rule of glassAnimations) expect(rule).toMatch(/animation:\s*land-frost\b/)
  })

  it('the landing frosts the glass without fading or moving it', () => {
    const frost = css.slice(css.indexOf('@keyframes land-frost'))
    const body = frost.slice(0, frost.indexOf('\n}') + 2)
    expect(body).toContain('backdrop-filter')
    expect(body).not.toMatch(/opacity|transform/)
  })
})
