import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { LOADER_LEAVE_MS, useLoaderExit } from '../../src/useLoaderExit'

/** Says whether the browser allows motion, the way the hook asks. */
function motion(allowed: boolean) {
  vi.stubGlobal('matchMedia', (q: string) => ({ matches: q.includes('no-preference') ? allowed : !allowed }))
}

beforeEach(() => {
  vi.useFakeTimers()
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('the loader leaving', () => {
  it('lingers as "leaving" when the data arrives, then goes', () => {
    motion(true)
    const { result, rerender } = renderHook(({ loading }) => useLoaderExit(loading), { initialProps: { loading: true } })
    expect(result.current).toBe('on')
    rerender({ loading: false })
    expect(result.current).toBe('leaving')
    act(() => { vi.advanceTimersByTime(LOADER_LEAVE_MS - 1) })
    expect(result.current).toBe('leaving')
    act(() => { vi.advanceTimersByTime(1) })
    expect(result.current).toBe('off')
  })

  it('is simply gone with reduced motion', () => {
    motion(false)
    const { result, rerender } = renderHook(({ loading }) => useLoaderExit(loading), { initialProps: { loading: true } })
    rerender({ loading: false })
    expect(result.current).toBe('off')
  })

  it('never shows when the data was there from the start, and comes back if the page waits again', () => {
    motion(true)
    const { result, rerender } = renderHook(({ loading }) => useLoaderExit(loading), { initialProps: { loading: false } })
    expect(result.current).toBe('off')
    rerender({ loading: true })
    expect(result.current).toBe('on')
    rerender({ loading: false })
    expect(result.current).toBe('leaving')
    // Waiting again mid-leave: the loader is back on, and the old timer can't switch it off.
    rerender({ loading: true })
    act(() => { vi.advanceTimersByTime(LOADER_LEAVE_MS * 2) })
    expect(result.current).toBe('on')
  })
})
