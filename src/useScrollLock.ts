import { useEffect } from 'react'

// How many pop-ups are open right now, so two at once unlock only when both close.
let locks = 0
// Where the page was scrolled to when the first pop-up opened.
let savedY = 0

/**
 * Stops the page behind a pop-up from scrolling while it's open (Dylan,
 * 2026-11-11). overflow: hidden alone isn't enough on iPhone Safari, which
 * still scrolls the page under a finger, so the body is pinned in place
 * with position: fixed at its current offset, and put back where it was on
 * close.
 */
export function useScrollLock(): void {
  useEffect(() => {
    const body = document.body
    locks += 1
    if (locks === 1) {
      savedY = window.scrollY
      body.style.position = 'fixed'
      body.style.top = `-${savedY}px`
      body.style.left = '0'
      body.style.right = '0'
      document.documentElement.dataset.modal = ''
    }
    return () => {
      locks -= 1
      if (locks > 0) return
      body.style.position = ''
      body.style.top = ''
      body.style.left = ''
      body.style.right = ''
      delete document.documentElement.dataset.modal
      // jsdom has no real scrolling; scrollTo there just logs a warning.
      if (typeof window.scrollTo === 'function' && !navigator.userAgent.includes('jsdom')) window.scrollTo(0, savedY)
    }
  }, [])
}
