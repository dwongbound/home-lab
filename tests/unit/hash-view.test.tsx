// Changing page: a tap fades the new page in and a swipe slides it in, in
// every browser and never in a view transition; with motion turned down it
// simply swaps.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen } from '@testing-library/react'
import { swipeToView, useHashView } from '../../src/useHashView'
import { swipeTarget } from '../../src/useSwipeNav'

const CHROME_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
const IPAD_UA = 'Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1'

/** Pretends to be a given browser. */
function asBrowser(ua: string) {
  vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(ua)
}

function Current() {
  return <p>{useHashView()}</p>
}

/** Changes the hash and fires hashchange the way a link click would. */
function go(hash: string) {
  act(() => {
    window.history.replaceState(null, '', hash)
    window.dispatchEvent(new HashChangeEvent('hashchange'))
  })
}

/** Swipes to a page; jsdom fires the hashchange a moment later. */
async function swipe(view: Parameters<typeof swipeToView>[0]) {
  await act(async () => {
    swipeToView(view)
    await new Promise((r) => setTimeout(r, 0))
  })
}

beforeEach(() => {
  // jsdom doesn't scroll; changing page scrolls to the top.
  vi.stubGlobal('scrollTo', vi.fn())
})
afterEach(() => {
  window.history.replaceState(null, '', '#')
  // @ts-expect-error jsdom has no view transitions; tests add and remove one
  delete document.startViewTransition
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
  delete document.documentElement.dataset.enter
})

describe('useHashView', () => {
  it('swaps the page straight away without view transitions', () => {
    render(<Current />)
    go('#services')
    expect(screen.getByText('services')).toBeInTheDocument()
  })

  it('a tap fades the new page in, with no view transition, in every browser', () => {
    for (const ua of [CHROME_UA, IPAD_UA]) {
      const start = vi.fn()
      Object.assign(document, { startViewTransition: start })
      vi.stubGlobal('matchMedia', (q: string) => ({ matches: !q.includes('reduce') }))
      asBrowser(ua)
      const { unmount } = render(<Current />)
      go(ua === CHROME_UA ? '#money' : '#home')
      expect(start).not.toHaveBeenCalled()
      expect(document.documentElement.dataset.enter).toBe('fade')
      unmount()
    }
  })

  it('a swipe slides the new page in from the side the finger went', async () => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: !q.includes('reduce') }))
    render(<Current />)
    await swipe('money')
    expect(screen.getByText('money')).toBeInTheDocument()
    expect(document.documentElement.dataset.enter).toBe('next')
    await swipe('home')
    expect(document.documentElement.dataset.enter).toBe('prev')
  })

  it('swipes to the neighbouring tab, stopping at either end', () => {
    expect(swipeTarget('overview', 'next')).toBe('home')
    expect(swipeTarget('home', 'prev')).toBe('overview')
    expect(swipeTarget('overview', 'prev')).toBeNull()
    expect(swipeTarget('preferences', 'next')).toBeNull()
  })

  it('changes page with no motion at all with reduced motion', () => {
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q.includes('reduce') }))
    render(<Current />)
    go('#claude')
    expect(screen.getByText('claude')).toBeInTheDocument()
    expect(document.documentElement.dataset.enter).toBeUndefined()
  })
})
