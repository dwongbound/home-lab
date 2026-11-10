// Changing page: inside a view transition where the browser has one,
// a plain swap where it doesn't or motion is turned down.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen } from '@testing-library/react'
import { useHashView } from '../../src/useHashView'

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
    render(<Current />)
    go('#schedule')
    expect(start).toHaveBeenCalledTimes(1)
    expect(screen.getByText('schedule')).toBeInTheDocument()
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
