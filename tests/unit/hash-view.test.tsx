// Changing page: inside a view transition where the browser has one,
// a plain swap where it doesn't or motion is turned down, and in Safari a
// swap with the panels' contents sliding in (its snapshots drop the glass).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen } from '@testing-library/react'
import { useHashView } from '../../src/useHashView'
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

  it('changes page inside a view transition when the browser has them', () => {
    const start = vi.fn((update: () => void) => { update(); return {} })
    Object.assign(document, { startViewTransition: start })
    vi.stubGlobal('matchMedia', () => ({ matches: false }))
    asBrowser(CHROME_UA)
    render(<Current />)
    go('#schedule')
    expect(start).toHaveBeenCalledTimes(1)
    expect(screen.getByText('schedule')).toBeInTheDocument()
  })

  it('in Safari, swaps without a view transition and slides the contents in from the right side', () => {
    const start = vi.fn()
    Object.assign(document, { startViewTransition: start })
    vi.stubGlobal('matchMedia', () => ({ matches: false }))
    asBrowser(IPAD_UA)
    render(<Current />)
    go('#money')
    expect(start).not.toHaveBeenCalled()
    expect(screen.getByText('money')).toBeInTheDocument()
    expect(document.documentElement.dataset.enter).toBe('next')
    go('#home')
    expect(document.documentElement.dataset.enter).toBe('prev')
  })

  it('swipes to the neighbouring tab, stopping at either end', () => {
    expect(swipeTarget('overview', 'next')).toBe('home')
    expect(swipeTarget('home', 'prev')).toBe('overview')
    expect(swipeTarget('overview', 'prev')).toBeNull()
    expect(swipeTarget('preferences', 'next')).toBeNull()
  })

  it('skips the transition with reduced motion', () => {
    const start = vi.fn()
    Object.assign(document, { startViewTransition: start })
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: q.includes('reduce') }))
    render(<Current />)
    go('#claude')
    expect(start).not.toHaveBeenCalled()
    expect(screen.getByText('claude')).toBeInTheDocument()
  })
})
