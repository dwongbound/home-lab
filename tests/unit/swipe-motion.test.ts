// While a finger is down the page's contents follow it, then either glide
// out (the swipe counted) or spring back. With reduced motion nothing moves.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearSwipe, dragTo, leave, settle } from '../../src/swipeMotion'

let main: HTMLElement

/** Pretends the reduce-motion setting is on or off. */
function reduceMotion(on: boolean) {
  vi.stubGlobal('matchMedia', () => ({ matches: on }))
}

beforeEach(() => {
  main = document.createElement('main')
  main.className = 'main'
  document.body.append(main)
  vi.useFakeTimers()
})
afterEach(() => {
  clearSwipe()
  main.remove()
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('swipe motion', () => {
  it('follows the finger part of the way and fades as it goes', () => {
    reduceMotion(false)
    dragTo(-200, false)
    expect(main.dataset.swipe).toBe('drag')
    expect(main.style.getPropertyValue('--swipe-x')).toBe('-120px')
    expect(Number(main.style.getPropertyValue('--swipe-o'))).toBeLessThan(1)
  })

  it('only gives a little at either end, like a rubber band', () => {
    reduceMotion(false)
    dragTo(200, true)
    expect(main.style.getPropertyValue('--swipe-x')).toBe('36px')
    expect(main.style.getPropertyValue('--swipe-o')).toBe('1.000')
  })

  it('glides out the way the finger went', () => {
    reduceMotion(false)
    leave('next')
    expect(main.dataset.swipe).toBe('leave')
    expect(main.style.getPropertyValue('--swipe-x')).toBe('-90px')
    expect(main.style.getPropertyValue('--swipe-o')).toBe('0.000')
  })

  it('springs back from a short swipe, then lets go of the page', () => {
    reduceMotion(false)
    dragTo(-40, false)
    settle()
    expect(main.dataset.swipe).toBe('settle')
    expect(main.style.getPropertyValue('--swipe-x')).toBe('0px')
    vi.advanceTimersByTime(500)
    expect(main.dataset.swipe).toBeUndefined()
    expect(main.style.getPropertyValue('--swipe-x')).toBe('')
  })

  it('moves nothing with reduced motion', () => {
    reduceMotion(true)
    dragTo(-200, false)
    leave('prev')
    expect(main.dataset.swipe).toBeUndefined()
  })
})
