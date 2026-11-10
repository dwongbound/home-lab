import { useEffect } from 'react'
import { VIEWS, type View } from './components/TopNav'
import { dragTo, leave, LEAVE_MS, motionWanted, settle } from './swipeMotion'

// Swipe left or right anywhere on the page to go to the next or previous
// tab, in the order of the pills. Built for the iPad on the wall, so it
// only counts a quick, clearly sideways swipe, and leaves alone anything
// that needs a sideways drag of its own (text boxes, sliders, the
// terminal, sideways-scrolling strips) and any open pop-up.
// While the finger is down the page's contents follow it (swipeMotion.ts).

// How far (px) a finger must travel sideways, and how much more sideways
// than up or down, before it counts as a swipe.
const MIN_DISTANCE = 70
const SIDEWAYS_RATIO = 1.6
// Longer than this (ms) is a slow drag, not a flick...
const MAX_DURATION = 700
// ...but a slow drag this share of the screen wide still counts.
const FAR_SHARE = 0.25
// How far (px) a finger moves before the page decides it's sideways or a scroll.
const DECIDE = 10
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
    // True once the finger has clearly gone sideways and the page follows it.
    let dragging = false
    let pending: ReturnType<typeof setTimeout> | undefined

    const onStart = (e: TouchEvent) => {
      start = null
      dragging = false
      if (e.touches.length !== 1) return
      const touch = e.touches[0]
      if (touch.clientX < EDGE || touch.clientX > window.innerWidth - EDGE) return
      const target = e.target instanceof Element ? e.target : null
      if (target?.closest(NO_SWIPE)) return
      if (document.querySelector('dialog[open]')) return
      if (inSidewaysScroller(target)) return
      start = { x: touch.clientX, y: touch.clientY, t: e.timeStamp }
    }

    const onMove = (e: TouchEvent) => {
      if (start === null || e.touches.length !== 1) return
      const touch = e.touches[0]
      const dx = touch.clientX - start.x
      const dy = touch.clientY - start.y
      if (!dragging) {
        // Up or down first: it's a scroll, so leave this touch alone.
        if (Math.abs(dy) > DECIDE && Math.abs(dy) * SIDEWAYS_RATIO > Math.abs(dx)) { start = null; return }
        if (Math.abs(dx) < DECIDE) return
        dragging = true
      }
      dragTo(dx, swipeTarget(view, dx < 0 ? 'next' : 'prev') === null)
    }

    const onEnd = (e: TouchEvent) => {
      if (start === null) return
      const touch = e.changedTouches[0]
      const dx = touch.clientX - start.x
      const dy = touch.clientY - start.y
      const quick = e.timeStamp - start.t <= MAX_DURATION
      const far = Math.abs(dx) >= window.innerWidth * FAR_SHARE
      start = null
      dragging = false
      // Finger moving left brings in the page to the right, like turning a page.
      const direction = dx < 0 ? 'next' : 'prev'
      const to = swipeTarget(view, direction)
      const counts = (quick || far) && Math.abs(dx) >= MIN_DISTANCE && Math.abs(dx) >= Math.abs(dy) * SIDEWAYS_RATIO
      if (!counts || !to) { settle(); return }
      // Let the contents glide out, then change page; the new one glides in.
      leave(direction)
      clearTimeout(pending)
      pending = setTimeout(() => onSwipe(to, direction), motionWanted() ? LEAVE_MS : 0)
    }

    const onCancel = () => {
      start = null
      dragging = false
      settle()
    }

    // Passive: the page never blocks scrolling to watch for a swipe.
    window.addEventListener('touchstart', onStart, { passive: true })
    window.addEventListener('touchmove', onMove, { passive: true })
    window.addEventListener('touchend', onEnd, { passive: true })
    window.addEventListener('touchcancel', onCancel, { passive: true })
    return () => {
      clearTimeout(pending)
      window.removeEventListener('touchstart', onStart)
      window.removeEventListener('touchmove', onMove)
      window.removeEventListener('touchend', onEnd)
      window.removeEventListener('touchcancel', onCancel)
    }
  }, [view, onSwipe])
}
