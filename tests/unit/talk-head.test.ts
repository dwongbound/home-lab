// server/talk-head.mjs: /talk is served with its own home-screen identity,
// so iOS's Add to Home Screen sees the Talk app, not the dashboard.
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { isTalkPagePath, talkHead } from '../../server/talk-head.mjs'

describe('the Talk page head', () => {
  it('knows the Talk page by its path, with or without a slash or folder', () => {
    expect(isTalkPagePath('/talk')).toBe(true)
    expect(isTalkPagePath('/talk/')).toBe(true)
    expect(isTalkPagePath('/lab/talk')).toBe(true)
    expect(isTalkPagePath('/')).toBe(false)
    expect(isTalkPagePath('/talking')).toBe(false)
  })

  it("swaps the dashboard's manifest, home-screen name and title for Talk's", () => {
    const html = talkHead(readFileSync('index.html', 'utf8'))
    expect(html).toContain('<link rel="manifest" href="./talk.webmanifest" />')
    expect(html).toContain('<meta name="apple-mobile-web-app-title" content="Talk" />')
    expect(html).toContain('<title>Talk to Jarvis</title>')
    expect(html).not.toContain('manifest.webmanifest"')
  })

  it('gives the two apps different ids, so the phone keeps both icons', () => {
    const dash = JSON.parse(readFileSync('public/manifest.webmanifest', 'utf8'))
    const talk = JSON.parse(readFileSync('public/talk.webmanifest', 'utf8'))
    expect(dash.id).not.toBe(talk.id)
    expect(talk.start_url).toBe('./talk')
    expect(talk.scope).toBe('./talk')
  })
})
