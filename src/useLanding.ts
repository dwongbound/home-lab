import { useLayoutEffect, useRef } from 'react'

// The landing: the first time real data arrives, the page arrives with it.
// The sky surges in from dark, the sun rises, the title sharpens out of a
// blur, the pill bar opens from the middle and the panels rise in one after
// another. All of it is CSS keyed on <html data-landing> (styles.css,
// "Landing"), so with reduced motion the attribute does nothing.
//
// Panels animate themselves, never anything around them, so their glass
// keeps blurring the sky while they move.

const LANDING_MS = 2600
const MAX_STAGGER = 10

/** Runs the landing once, when `ready` first turns true. */
export function useLanding(ready: boolean) {
  const done = useRef(false)

  // Before paint, so the first frame of the page is already the first frame
  // of the landing rather than a flash of the finished page.
  useLayoutEffect(() => {
    if (!ready || done.current) return
    done.current = true
    const root = document.documentElement
    document.querySelectorAll<HTMLElement>('.main .glass').forEach((el, i) => {
      el.style.setProperty('--i', String(Math.min(i, MAX_STAGGER)))
    })
    root.setAttribute('data-landing', '')
    const id = setTimeout(() => root.removeAttribute('data-landing'), LANDING_MS)
    return () => { clearTimeout(id); root.removeAttribute('data-landing') }
  }, [ready])
}
