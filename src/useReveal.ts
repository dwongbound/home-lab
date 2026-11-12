import { useEffect, type RefObject } from 'react'

// Panels fade in as they first scroll into view (Dylan, 2026-11-11).
//
// A glass panel that starts below the screen gets data-reveal="wait"
// (frame clear, contents hidden); when it scrolls into view it becomes
// data-reveal="in" and its contents play a short, time-based opacity fade
// (styles.css; the glass frame itself never animates). Each panel reveals
// once. Panels already on screen are marked "shown" and never animate.
//
// This replaces a CSS scroll-driven reveal (animation-timeline: view()),
// which Safari on the iPhone skipped and which, in Chromium, restarted about
// 3 s after load and dropped the lower panels back down (the "shake").

// Reveal once the panel's top is a little way up from the bottom edge, so
// the fade is seen rather than happening just out of sight.
const ROOT_MARGIN = '0px 0px -8% 0px'

/** Whether the user asked for less motion (then nothing is hidden). */
function prefersLessMotion(): boolean {
  return typeof matchMedia !== 'function' || !matchMedia('(prefers-reduced-motion: no-preference)').matches
}

/** Marks below-the-screen glass panels inside `main` to fade in when scrolled to. `mainKey` changes when the main element is replaced. */
export function useReveal(main: RefObject<HTMLElement | null>, mainKey: string): void {
  useEffect(() => {
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
    // ones are picked up as they appear. Only ones starting off screen wait.
    const mark = () => {
      for (const panel of root.querySelectorAll<HTMLElement>('.glass:not([data-reveal])')) {
        const below = panel.getBoundingClientRect().top > window.innerHeight
        panel.setAttribute('data-reveal', below ? 'wait' : 'shown')
        if (below) seen.observe(panel)
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
