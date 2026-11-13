// The backdrop must not move when iOS Safari's toolbar slides in and out:
// it is sized to the large viewport (lvh), not the visible one (vh / inset).
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const css = readFileSync(resolve(__dirname, '../../src/styles.css'), 'utf8')

describe('backdrop size', () => {
  it('sizes the sky, sun and ridge to the large viewport', () => {
    const block = css.match(/@supports \(height: 100lvh\) \{([\s\S]*?)\n\}/)?.[1] ?? ''
    expect(block).toMatch(/\.backdrop \{[^}]*height: 100lvh/)
    expect(block).toMatch(/\.backdrop__sun \{[^}]*70lvmax/)
    expect(block).toMatch(/\.backdrop__ridge \{[^}]*height: 22lvh; bottom: 18lvh/)
  })

  it('shades the whole /talk screen, not just the part above Safari’s toolbar', () => {
    const blocks = [...css.matchAll(/@supports \(height: 100lvh\) \{([\s\S]*?)\n\}/g)].map((m) => m[1]).join('\n')
    expect(blocks).toMatch(/\.dialog\.dialog--chat\[data-page\] \{[^}]*height: 100lvh/)
    expect(blocks).toMatch(/padding-bottom: max\([^;]*100lvh - 100dvh/)
  })
})
