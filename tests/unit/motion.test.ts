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

  it('fades one sky into the next slowly, only inside the no-preference block', () => {
    const block = motionBlock(css)
    expect(css).toMatch(/@property --sky-top \{ syntax: '<color>'/)
    expect(block).toMatch(/\.backdrop \{[^}]*transition-property: --sky-top[^}]*transition-duration: 120s/)
    expect(css.replace(block, '')).not.toMatch(/\.backdrop[^{]*\{[^}]*transition/)
  })

  it('appears without moving: reveals are pure fades, nothing behind the glass moves, layers stay put', () => {
    const block = motionBlock(css)
    expect(css).toMatch(/@keyframes reveal \{ from \{ opacity: 0; \} \}/)
    expect(css).toMatch(/@keyframes land-sun \{ from \{ opacity: 0; \} \}/)
    expect(css).toMatch(/@keyframes land-title \{ from \{ opacity: 0; \} \}/)
    expect(css).toMatch(/@keyframes land-rise \{ from \{ opacity: 0; \} \}/)
    expect(css).not.toMatch(/land-ridge/)
    expect(block).toMatch(/\.main \.glass > \* \{ will-change: opacity; \}/)
  })

  it('leaves the top bar alone on landing: it is already showing over the loader', () => {
    expect(motionBlock(css)).not.toMatch(/data-landing\][^{]*(topbar|pill)/)
  })

  it('fades panel contents in place on landing, without moving them', () => {
    const block = motionBlock(css)
    expect(block).toMatch(/\.shell\[data-landing\] \.main \.glass > \*\s*\{\s*animation: land-fade /)
    expect(css).toMatch(/@keyframes land-fade \{ from \{ opacity: 0; \} \}/)
  })

  it('fades panels in as they scroll into view, never fading the glass itself', () => {
    const block = motionBlock(css)
    // useReveal sets data-reveal; the glass only frosts, its contents fade up,
    // and a waiting panel holds at the first frame until it is reached.
    expect(block).toMatch(/\.glass\[data-reveal='in'\] \{ animation: land-frost /)
    expect(block).toMatch(/\.glass\[data-reveal='in'\] > \* \{ animation: reveal /)
    expect(block).toMatch(/\.glass\[data-reveal='wait'\] > \* \{ animation-play-state: paused; \}/)
    // No scroll-driven timeline: Safari skipped it, and in Chromium it took
    // over from the landing ~3 s after load and shook the lower panels.
    expect(css).not.toMatch(/animation-timeline/)
    // Fading a glass panel, or anything holding one, breaks its blur. Glass
    // may only frost (no opacity or transform, checked below) or slide itself
    // in when the page changes (translate only, checked below).
    const glassAnimations = [...block.matchAll(/\.glass(?:\[[^\]]*\])?\s*\{([^}]*)\}/g)].map((m) => m[1]).filter((rule) => /animation:/.test(rule))
    for (const rule of glassAnimations) expect(rule).toMatch(/animation:\s*(land-frost|enter-glass-from-(right|left))\b/)
  })

  it('glass slides itself in on a page change, never fading', () => {
    for (const side of ['right', 'left']) {
      const rule = css.match(new RegExp(`@keyframes enter-glass-from-${side} \\{([^\n]*)\\}`))
      expect(rule?.[1]).toMatch(/translate: -?56px 0/)
      expect(rule?.[1]).not.toMatch(/opacity|transform|filter/)
    }
  })

  it('the landing frosts the glass without fading or moving it', () => {
    const frost = css.slice(css.indexOf('@keyframes land-frost'))
    const body = frost.slice(0, frost.indexOf('\n}') + 2)
    // Growing the blur made Safari re-snap the sky behind every frame (a shake).
    expect(body).not.toMatch(/opacity|transform|backdrop-filter/)
    // The tint fades through registered colours: `background` can't blend
    // from a colour to the glass gradient, so it snapped dark mid-landing.
    expect(body).not.toMatch(/background/)
    expect(body).toMatch(/--glass: transparent; --glass-strong: transparent/)
    expect(css).toMatch(/@property --glass \{ syntax: '<color>'/)
    expect(css).toMatch(/@property --glass-strong \{ syntax: '<color>'/)
  })
})
