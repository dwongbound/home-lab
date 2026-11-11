import { forwardRef, useEffect, useImperativeHandle, useRef, type CSSProperties } from 'react'

// Jarvis's orb: the same glacier-blue ball as the first-load loader, but
// alive. It breathes slowly when idle, its orbits spin while Jarvis thinks,
// and while Jarvis talks it swells with each word (pulse()) and lets go.
// Only transform and opacity move, and only inside the reduced-motion
// no-preference block, so with reduced motion it's a still, glowing orb.

export type OrbState = 'idle' | 'thinking' | 'speaking'

export interface OrbHandle {
  /** One beat of speech: a word arriving, or a loud moment in the voice. 0..1. */
  pulse: (amount?: number) => void
}

interface Props {
  state: OrbState
  /** Diameter of the core in px; the halo and orbits scale with it. */
  size: number
}

/** True when the browser asks for less motion (then the orb stays still). */
function prefersLessMotion(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** The orb. Its loudness is set straight on the element, so pulses never re-render React. */
export const JarvisOrb = forwardRef<OrbHandle, Props>(function JarvisOrb({ state, size }, ref) {
  const el = useRef<HTMLSpanElement>(null)
  const level = useRef(0)
  const frame = useRef(0)

  // Each frame the level eases back toward silence, so a burst of words
  // reads as speech rather than a flicker. The loop stops itself at rest.
  function tick() {
    level.current *= 0.9
    if (level.current < 0.01) level.current = 0
    el.current?.style.setProperty('--level', level.current.toFixed(3))
    if (level.current > 0) frame.current = requestAnimationFrame(tick)
    else frame.current = 0
  }

  useImperativeHandle(ref, () => ({
    pulse(amount = 1) {
      if (prefersLessMotion()) return
      level.current = Math.min(1, Math.max(level.current, amount))
      if (frame.current === 0) frame.current = requestAnimationFrame(tick)
    },
  }), [])

  // Stop the loop when the orb goes away.
  useEffect(() => () => cancelAnimationFrame(frame.current), [])

  return (
    <span ref={el} className="orb" data-state={state} style={{ '--orb': `${size}px` } as CSSProperties} aria-hidden="true">
      <span className="orb__halo" />
      <span className="orb__wave" />
      <span className="orb__orbit orb__orbit--a"><span className="orb__spark" /></span>
      <span className="orb__orbit orb__orbit--b"><span className="orb__spark" /></span>
      <span className="orb__core" />
    </span>
  )
})
