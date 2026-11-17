import { forwardRef, useEffect, useImperativeHandle, useRef, type CSSProperties } from 'react'
import { ORB_POINTS, ORB_REACH, orbDot, orbLinks, orbLook, orbPoints, orbRipple } from '../lib/orb'

/** The constellation's lines never change (turning keeps distances), so they're worked out once. */
const LINKS = orbLinks(orbPoints(ORB_POINTS, 0))

// Jarvis's orb, design D (Dylan, 2026-11-16, the iPhone app's orb): a
// see-through glass core inside a constellation of points that turns in 3D
// around it. Points behind the core are drawn on the back canvas, so they
// show through the glass; points in front pass over it on the front canvas.
// It sits still when idle, turns gently while listening (tinted green, your
// turn), fast and tight while thinking, wide and warm with the amber sweep
// while he's off doing something slow, and while Jarvis talks it swells
// with each word (pulse()) and lets go.
// With reduced motion it's drawn once and never moves.

export type OrbState = 'idle' | 'listening' | 'thinking' | 'working' | 'speaking'

export interface OrbHandle {
  /** One beat of speech: a word arriving, or a loud moment in the voice. 0..1. */
  pulse: (amount?: number) => void
}

interface Props {
  state: OrbState
  /** Diameter of the core: px, or any CSS length (e.g. a clamp() that follows the screen). The constellation scales with it. */
  size: number | string
}

/** The core's size as CSS: a number is px, a string is used as written. */
function orbSize(size: number | string): string {
  if (typeof size === 'number') return `${size}px`
  return size
}

/** True when the browser asks for less motion (then the orb stays still). */
function prefersLessMotion(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return true
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** The orb. Its loudness and turning live in refs, so frames never re-render React. */
export const JarvisOrb = forwardRef<OrbHandle, Props>(function JarvisOrb({ state, size }, ref) {
  const el = useRef<HTMLSpanElement>(null)
  const back = useRef<HTMLCanvasElement>(null)
  const front = useRef<HTMLCanvasElement>(null)
  // What the voice is doing (target) and what the orb shows (level), which
  // glides toward it, so loudness changes read as smooth swells, not jumps.
  const level = useRef(0)
  const target = useRef(0)
  const angle = useRef(0)
  const frame = useRef(0)
  const last = useRef(0)
  const stateRef = useRef(state)
  stateRef.current = state

  /** Draws the constellation as it is now onto both canvases. */
  function draw() {
    const host = el.current
    const b = back.current
    const f = front.current
    if (!host || !b || !f) return
    const core = host.getBoundingClientRect().width
    if (core <= 0) return
    const look = orbLook(stateRef.current)
    const ratio = Math.min(window.devicePixelRatio || 1, 2)
    const side = b.getBoundingClientRect().width
    const reach = core * ORB_REACH * look.spread
    const t = performance.now() / 1000
    const state = stateRef.current
    // The dots react to your voice only; his voice moves just the core.
    const dotLevel = state === 'listening' ? level.current : 0
    // Each point where it sits this frame, rippled by the voice.
    const placed = orbPoints(ORB_POINTS, angle.current).map((p, i) => {
      const r = reach * orbRipple(state, i, level.current, t)
      return { x: side / 2 + p.x * r, y: side / 2 + p.y * r, z: p.z }
    })
    const [r, g, bl] = look.color
    const lineWidth = Math.max(core / 160, 0.5)
    for (const canvas of [b, f]) {
      const px = Math.round(side * ratio)
      if (canvas.width !== px) {
        canvas.width = px
        canvas.height = px
      }
      const ctx = canvas.getContext('2d')
      if (!ctx) continue
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
      ctx.clearRect(0, 0, side, side)
      const inFront = canvas === f
      // Faint lines between neighbouring points, brighter nearer you and
      // while a voice is moving it.
      ctx.lineWidth = lineWidth
      for (const [i, j] of LINKS) {
        const a = placed[i]
        const c = placed[j]
        const z = (a.z + c.z) / 2
        if ((z >= 0) !== inFront) continue
        const near = (z + 1) / 2
        const alpha = (0.05 + near * 0.16) * (1 + dotLevel * 0.8)
        ctx.strokeStyle = `rgba(${r}, ${g}, ${bl}, ${alpha.toFixed(3)})`
        ctx.beginPath()
        ctx.moveTo(a.x, a.y)
        ctx.lineTo(c.x, c.y)
        ctx.stroke()
      }
      for (const p of placed) {
        if ((p.z >= 0) !== inFront) continue
        const dot = orbDot(p, core)
        ctx.fillStyle = `rgba(${r}, ${g}, ${bl}, ${dot.alpha.toFixed(3)})`
        ctx.beginPath()
        ctx.arc(p.x, p.y, dot.radius * (1 + dotLevel * 0.4), 0, Math.PI * 2)
        ctx.fill()
      }
    }
    host.style.setProperty('--level', level.current.toFixed(3))
  }

  /**
   * One frame: turn by the state's speed, ease the speech level back toward
   * silence, draw. The loop stops itself when there's nothing left to move
   * (idle and quiet), so nothing loops forever inside the glass.
   */
  function tick(now: number) {
    const dt = last.current === 0 ? 0 : Math.min((now - last.current) / 1000, 0.1)
    last.current = now
    const look = orbLook(stateRef.current)
    angle.current += look.speed * dt
    // Eases back toward silence quickly, so it follows each rise and fall of the voice.
    // The voice's loudness fades on its own; the orb glides after it, rising
    // a little faster than it falls (like breath), framerate-independent.
    target.current *= Math.pow(0.04, dt)
    const rate = target.current > level.current ? 4.5 : 2.5
    level.current += (target.current - level.current) * (1 - Math.exp(-rate * dt))
    if (target.current < 0.005 && level.current < 0.005) {
      target.current = 0
      level.current = 0
    }
    draw()
    if (look.speed > 0 || level.current > 0 || target.current > 0) frame.current = requestAnimationFrame(tick)
    else stop()
  }

  /** Starts the loop if it isn't running. */
  function start() {
    if (frame.current !== 0 || prefersLessMotion()) return
    last.current = 0
    frame.current = requestAnimationFrame(tick)
  }

  /** Stops the loop. */
  function stop() {
    cancelAnimationFrame(frame.current)
    frame.current = 0
    last.current = 0
  }

  useImperativeHandle(ref, () => ({
    pulse(amount = 1) {
      if (prefersLessMotion()) return
      target.current = Math.min(1, Math.max(target.current, amount))
      start()
    },
  }), [])

  // A new state redraws at once (new colour) and moves if that state moves.
  useEffect(() => {
    draw()
    if (orbLook(state).speed > 0) start()
  }, [state])

  // Redraw when the orb changes size (the /talk orb follows the screen), and
  // stop the loop when it goes away.
  useEffect(() => {
    const host = el.current
    let observer: ResizeObserver | null = null
    if (host && typeof ResizeObserver === 'function') {
      observer = new ResizeObserver(() => draw())
      observer.observe(host)
    }
    return () => {
      observer?.disconnect()
      stop()
    }
  }, [])

  return (
    <span ref={el} className="orb" data-state={state} style={{ '--orb': orbSize(size) } as CSSProperties} aria-hidden="true">
      <span className="orb__halo" />
      <span className="orb__scan" />
      <canvas ref={back} className="orb__points" />
      <span className="orb__core" />
      <canvas ref={front} className="orb__points" />
    </span>
  )
})
