// Which address draws the full-screen Talk page.
import { describe, expect, it } from 'vitest'
import { isTalkPage } from '../../src/lib/talkPage'

describe('isTalkPage', () => {
  it('is /talk (with or without a slash), or #talk for a build served from a folder', () => {
    expect(isTalkPage({ pathname: '/talk', hash: '' })).toBe(true)
    expect(isTalkPage({ pathname: '/talk/', hash: '' })).toBe(true)
    expect(isTalkPage({ pathname: '/preview/index.html', hash: '#talk' })).toBe(true)
  })

  it('is not the dashboard or its tabs', () => {
    expect(isTalkPage({ pathname: '/', hash: '' })).toBe(false)
    expect(isTalkPage({ pathname: '/', hash: '#services' })).toBe(false)
    expect(isTalkPage({ pathname: '/talking', hash: '' })).toBe(false)
  })
})
