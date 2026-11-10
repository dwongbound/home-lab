import { useEffect } from 'react'
import { VIEWS, type View } from './components/TopNav'

// Swipe left or right anywhere on the page to go to the next or previous
// tab, in the order of the pills. Built for the iPad on the wall, so it
// only counts a quick, clearly sideways swipe, and leaves alone anything
// that needs a sideways drag of its own (text boxes, sliders, the
// terminal, sideways-scrolling strips) and any open pop-up.

// How far (px) a finger must travel sideways, and how much more sideways
// than up or down, before it counts as a swipe.
const MIN_DISTANCE = 70
const SIDEWAYS_RATIO = 1.6
// Longer than this (ms) is a slow drag, not a swipe.
const MAX_DURATION = 700
// Touches starting this close (px) to the screen's edge are the system's
// own gestures (Safari's back/forward, the iPad's app switcher).
const EDGE = 24

/** Elements whose own touch handling a swipe must never override. */
const NO_SWIPE = 'input, textarea, select, [role="slider"], input[type="range"], iframe, .terminal, [data-no-swipe]'

/** The tab next to `view` in the direction swiped, or null at either end. */
export function swipeTarget(view: View, direction: 'next' | 'prev'): View | null {
  const i = VIEWS.findIndex((v) => v.id === view)
  const j = direction === 'next' ? i + 1 : i - 1
  if (i < 0 || j < 0 || j >= VIEWS.length) return null
  return VIEWS[j].id
}

/** True when the touch started inside something that scrolls sideways itself. */
function inSidewaysScroller(el: Element | null): boolean {
  for (let node = el; node && node !== document.body; node = node.parentElement) {
    const overflowX = getComputedStyle(node).overflowX
    if ((overflowX === 'auto' || overflowX === 'scroll') && node.scrollWidth > node.clientWidth) return true
  }
  return false
}

/** Turns sideways swipes into tab changes. `onSwipe` gets the tab to go to. */
export function useSwipeNav(view: View, onSwipe: (to: View, direction: 'next' | 'prev') => void): void {
  useEffect(() => {
    let start: { x: number; y: number; t: number } | null = null

    const onStart = (e: TouchEvent) => {
      start = null
      if (e.touches.length !== 1) return
      const touch = e.touches[0]
      if (touch.clientX < EDGE || touch.clientX > window.innerWidth - EDGE) return
      const target = e.target instanceof Element ? e.target : null
      if (target?.closest(NO_SWIPE)) return
      if (document.querySelector('dialog[open]')) return
      if (inSidewaysScroller(target)) return
      start = { x: touch.clientX, y: touch.clientY, t: e.timeStamp }
    }

    const onEnd = (e: TouchEvent) => {
      if (start === null) return
      const touch = e.changedTouches[0]
      const dx = touch.clientX - start.x
      const dy = touch.clientY - start.y
      const quick = e.timeStamp - start.t <= MAX_DURATION
      start = null
      if (!quick || Math.abs(dx) < MIN_DISTANCE || Math.abs(dx) < Math.abs(dy) * SIDEWAYS_RATIO) return
      // Finger moving left brings in the page to the right, like turning a page.
      const direction = dx < 0 ? 'next' : 'prev'
      const to = swipeTarget(view, direction)
      if (to) onSwipe(to, direction)
    }

    const onCancel = () => { start = null }

    // Passive: the page never blocks scrolling to watch for a swipe.
    window.addEventListener('touchstart', onStart, { passive: true })
    window.addEventListener('touchend', onEnd, { passive: true })
    window.addEventListener('touchcancel', onCancel, { passive: true })
    return () => {
      window.removeEventListener('touchstart', onStart)
      window.removeEventListener('touchend', onEnd)
      window.removeEventListener('touchcancel', onCancel)
    }
  }, [view, onSwipe])
}
