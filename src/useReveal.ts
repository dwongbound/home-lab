import { useLayoutEffect, type RefObject } from 'react'

// Panels fade in as they first scroll into view (Dylan, 2026-11-11).
//
// A glass panel that starts below the screen gets data-reveal="wait"
// (frame clear, contents hidden); when it scrolls into view it becomes
// data-reveal="in" and its contents play a short, time-based opacity fade
// (styles.css; the glass frame itself never animates). Each panel reveals
// once. Panels on screen as the page first appears fade in the same way,
// staggered; ones that mount on screen later are marked "shown".
//
// This replaces a CSS scroll-driven reveal (animation-timeline: view()),
// which Safari on the iPhone skipped and which, in Chromium, restarted about
// 3 s after load and dropped the lower panels back down (the "shake").

// Reveal once the panel's top is a little way up from the bottom edge, so
// the fade is seen rather than happening just out of sight.
const ROOT_MARGIN = '0px 0px -8% 0px'

// Panels on screen when the page first appears, or a new page is shown,
// fade in too, each a little after the one before (Dylan liked those fades,
// 2026-11-12). The stagger is
// capped so the last panel isn't kept waiting.
const APPEAR_MS = 1500
const MAX_STAGGER = 6

/** Whether the user asked for less motion (then nothing is hidden). */
function prefersLessMotion(): boolean {
  return typeof matchMedia !== 'function' || !matchMedia('(prefers-reduced-motion: no-preference)').matches
}

/** Marks glass panels inside `main` to fade in: on screen now, or when scrolled to. `mainKey` changes with the main element or the page. */
export function useReveal(main: RefObject<HTMLElement | null>, mainKey: string): void {
  // A layout effect, so panels are marked before the first paint: marked
  // after it (useEffect), they showed for a frame and then faded, which
  // read as a flash rather than a fade on Dylan's iPhone (2026-11-12).
  useLayoutEffect(() => {
    const root = main.current
    if (!root || typeof IntersectionObserver !== 'function' || prefersLessMotion()) return

    const seen = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.setAttribute('data-reveal', 'in')
        seen.unobserve(entry.target)
      }
    }, { rootMargin: ROOT_MARGIN })

    // Panels mount later too (data arriving, a section opening), so new
    // ones are picked up as they appear. Ones starting off screen wait.
    // Ones on screen fade in, one after another, only while the page is
    // first appearing; after that they simply show.
    const started = performance.now()
    let onScreen = 0
    const mark = () => {
      const appearing = performance.now() - started < APPEAR_MS
      for (const panel of root.querySelectorAll<HTMLElement>('.glass:not([data-reveal])')) {
        const below = panel.getBoundingClientRect().top > window.innerHeight
        if (below) {
          panel.setAttribute('data-reveal', 'wait')
          seen.observe(panel)
        } else if (appearing) {
          panel.style.setProperty('--reveal-i', String(Math.min(onScreen++, MAX_STAGGER)))
          panel.setAttribute('data-reveal', 'in')
        } else {
          panel.setAttribute('data-reveal', 'shown')
        }
      }
    }
    mark()
    const added = new MutationObserver(mark)
    added.observe(root, { childList: true, subtree: true })
    return () => {
      added.disconnect()
      seen.disconnect()
    }
  }, [main, mainKey])
}
