// What a swipe looks like while the finger is down and just after: the
// page's panels follow the finger and fade a little, then either glide
// out the way you swiped (and the new page glides in from the other side,
// see playEnter in useHashView.ts) or spring back if the swipe was too short.
//
// Whole panels move (with `translate`, never fading the glass) and so
// does the page title; what's inside each panel fades a little. The
// numbers live in two CSS variables on <main>, read by styles.css; the
// phase is <main data-swipe="drag|leave|settle">.

/** How long (ms) the contents take to glide out once a swipe counts. */
export const LEAVE_MS = 200
// How long the spring back takes (matches styles.css).
const SETTLE_MS = 460
// How far (px) the contents glide before the new page comes in.
const LEAVE_PX = 90

let timer: ReturnType<typeof setTimeout> | undefined

/** True when motion is wanted (no reduce-motion setting). */
export function motionWanted(): boolean {
  return !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

/** The page's <main>, where the swipe variables go, or null before it's drawn. */
function main(): HTMLElement | null {
  return document.querySelector<HTMLElement>('main.main')
}

/** Sets the phase and where the contents are: `x` px sideways at `opacity`. */
function place(phase: 'drag' | 'leave' | 'settle', x: number, opacity: number): void {
  const el = main()
  if (!el) return
  el.dataset.swipe = phase
  el.style.setProperty('--swipe-x', `${Math.round(x)}px`)
  el.style.setProperty('--swipe-o', opacity.toFixed(3))
}

/**
 * While the finger is down: the contents sit `shift` px to the side and
 * fade the further they go. `edge` is true when there's no tab that way,
 * so the page only gives a little, like a rubber band.
 */
export function dragTo(shift: number, edge: boolean): void {
  if (!motionWanted()) return
  clearTimeout(timer)
  if (edge) {
    place('drag', shift * 0.18, 1)
    return
  }
  const fade = Math.min(Math.abs(shift) / (window.innerWidth * 0.55), 0.55)
  place('drag', shift * 0.6, 1 - fade)
}

/** The swipe counted: the contents glide out the way the finger went. */
export function leave(direction: 'next' | 'prev'): void {
  if (!motionWanted()) return
  clearTimeout(timer)
  place('leave', direction === 'next' ? -LEAVE_PX : LEAVE_PX, 0)
}

/** The swipe was too short: the contents spring back to where they were. */
export function settle(): void {
  const el = main()
  if (!el || !el.dataset.swipe) return
  place('settle', 0, 1)
  clearTimeout(timer)
  timer = setTimeout(clearSwipe, SETTLE_MS)
}

/** Puts the contents back with no motion: the new page is taking over. */
export function clearSwipe(): void {
  clearTimeout(timer)
  const el = main()
  if (!el) return
  delete el.dataset.swipe
  el.style.removeProperty('--swipe-x')
  el.style.removeProperty('--swipe-o')
}
