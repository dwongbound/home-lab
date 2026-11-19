import { useEffect, useRef, useState } from 'react'

// The first-load loader doesn't just vanish when the page's data arrives
// (Dylan, 2026-11-18: "when i load the page it should smoothly transition").
// It stays on top for a moment as "leaving": the orb lifts away and fades
// while the panels fade in underneath (useReveal). With reduced motion
// there's no leaving: the loader is simply gone.

/** Where the loader is: showing, on its way out over the page, or gone. */
export type LoaderPhase = 'on' | 'leaving' | 'off'

/** How long the loader takes to leave. Keep in step with `loader-orb-out` in styles.css. */
export const LOADER_LEAVE_MS = 700

/** Whether the user asked for less motion (then the loader never lingers). */
function prefersLessMotion(): boolean {
  return typeof matchMedia !== 'function' || !matchMedia('(prefers-reduced-motion: no-preference)').matches
}

/** The loader's phase, given whether the page is still waiting for its first data. */
export function useLoaderExit(loading: boolean): LoaderPhase {
  const [phase, setPhase] = useState<LoaderPhase>(loading ? 'on' : 'off')
  // Whether the loader has been on screen: only then is there anything to see leave.
  const shown = useRef(loading)

  useEffect(() => {
    if (loading) {
      shown.current = true
      setPhase('on')
      return
    }
    if (!shown.current) return
    shown.current = false
    if (prefersLessMotion()) {
      setPhase('off')
      return
    }
    setPhase('leaving')
    const id = setTimeout(() => setPhase('off'), LOADER_LEAVE_MS)
    return () => clearTimeout(id)
  }, [loading])

  return phase
}
