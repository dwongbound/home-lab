import { forwardRef, useEffect, useImperativeHandle, useRef, type CSSProperties } from 'react'
import { ORB_POINTS, ORB_REACH, ORB_SHELL_SWELL, OrbMotion, orbDot, orbLinks, orbPoints } from '../lib/orb'

/** The constellation's lines never change (turning keeps distances), so they're worked out once. */
const LINKS = orbLinks(orbPoints(ORB_POINTS, 0))

// Jarvis's orb, design D (Dylan, 2026-11-16, the iPhone app's orb): a
// see-through glass core inside a constellation of points that turns in 3D
// around it. Points behind the core are drawn on the back canvas, so they
// show through the glass; points in front pass over it on the front canvas.
// One continuous animation, the same as the app's (OrbMotion in lib/orb.ts):
// still when idle; a slow wandering tumble while he listens in silence or
// waits for "Hey Jarvis"; held still and swelling as one while you talk;
// spinning upright while he thinks, works (amber sweep) or speaks, when
// only the core swells with his voice (pulse()). Every change eases.
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
  /** Paused on an open line, waiting for "Hey Jarvis": the idle orb tumbles slowly instead of sitting still. */
  waiting?: boolean
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
export const JarvisOrb = forwardRef<OrbHandle, Props>(function JarvisOrb({ state, size, waiting = false }, ref) {
  const el = useRef<HTMLSpanElement>(null)
  const back = useRef<HTMLCanvasElement>(null)
  const front = useRef<HTMLCanvasElement>(null)
  // What the voice is doing right now (0..1); it fades by itself between
  // pulses, and OrbMotion smooths it into the swells that are drawn.
  const voice = useRef(0)
  const motion = useRef<OrbMotion | null>(null)
  if (motion.current === null) motion.current = new OrbMotion(state)
  const frame = useRef(0)
  const last = useRef(0)
  const stateRef = useRef(state)
  stateRef.current = state
  const waitingRef = useRef(waiting)
  waitingRef.current = waiting

  /** Draws the constellation as it is now onto both canvases. */
  function draw() {
    const host = el.current
    const b = back.current
    const f = front.current
    const now = motion.current
    if (!host || !b || !f || !now) return
    const core = host.getBoundingClientRect().width
    if (core <= 0) return
    const ratio = Math.min(window.devicePixelRatio || 1, 2)
    const side = b.getBoundingClientRect().width
    // Your voice swells the whole shell as one; nothing moves dot by dot.
    const heard = now.shellVoice
    const reach = core * ORB_REACH * now.spread * (1 + heard * ORB_SHELL_SWELL)
    const placed = now.points().map((p) => ({ x: side / 2 + p.x * reach, y: side / 2 + p.y * reach, z: p.z }))
    const [r, g, bl] = now.color.map((part) => Math.round(part))
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
      // while your voice is moving it.
      ctx.lineWidth = lineWidth
      for (const [i, j] of LINKS) {
        const a = placed[i]
        const c = placed[j]
        const z = (a.z + c.z) / 2
        if ((z >= 0) !== inFront) continue
        const near = (z + 1) / 2
        const alpha = (0.05 + near * 0.16) * (1 + heard * 0.8)
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
        ctx.arc(p.x, p.y, dot.radius * (1 + heard * 0.35), 0, Math.PI * 2)
        ctx.fill()
      }
    }
    // The core (CSS) swells and brightens with Jarvis's voice only.
    host.style.setProperty('--level', now.coreVoice.toFixed(3))
  }

  /**
   * One frame: let the voice fade toward silence, step the motion, draw.
   * The loop stops itself when there's nothing left to move (idle, quiet
   * and run down), so nothing loops forever inside the glass.
   */
  function tick(now: number) {
    const dt = last.current === 0 ? 0 : Math.min((now - last.current) / 1000, 0.1)
    last.current = now
    voice.current *= Math.pow(0.04, dt)
    if (voice.current < 0.005) voice.current = 0
    const input = { state: stateRef.current, waiting: waitingRef.current, level: voice.current }
    motion.current?.step(input, dt)
    draw()
    if (voice.current > 0 || !motion.current?.resting(input)) frame.current = requestAnimationFrame(tick)
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
      voice.current = Math.min(1, Math.max(voice.current, amount))
      start()
    },
  }), [])

  // A new state eases in (the loop runs until it has settled). With reduced
  // motion it's drawn once in the new state's look.
  useEffect(() => {
    if (prefersLessMotion()) motion.current?.snap(state)
    draw()
    start()
  }, [state, waiting])

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
