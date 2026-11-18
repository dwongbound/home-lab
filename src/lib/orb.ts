// Jarvis's orb, design D (Dylan, 2026-11-16): a see-through glass core
// inside a constellation of points that turns in 3D around it. The same
// orb as the iPhone app (ios/App/OrbView.swift); keep the two in step.
//
// These are the sums; JarvisOrb.tsx draws them on two canvases, one behind
// the glass core and one in front of it.

import type { OrbState } from '../components/JarvisOrb'

/** One point of the constellation: x and y on the screen, z toward you, each -1..1. */
export interface OrbPoint { x: number; y: number; z: number }

/** How many points the constellation has. */
export const ORB_POINTS = 60

/** How far the constellation reaches, as a share of the core's diameter (the core's edge is 0.5). */
export const ORB_REACH = 0.9

/**
 * How each state looks: the points' colour (r, g, b), how fast the
 * constellation turns (radians a second), and how far out it sits (1 = normal).
 * `speed` is the upright spin while he thinks, works or speaks; listening
 * and waiting tumble instead (OrbMotion). Idle doesn't turn at all: the orb
 * sits inside a glass panel, and a loop that never stops makes iOS redraw
 * that panel's blur every frame (Dylan's iPhone, 2026-11-12).
 */
export function orbLook(state: OrbState): { color: [number, number, number]; speed: number; spread: number } {
  if (state === 'listening') return { color: [196, 236, 214], speed: 0.35, spread: 1 }
  if (state === 'thinking') return { color: [236, 230, 255], speed: 1.4, spread: 0.9 }
  if (state === 'working') return { color: [250, 226, 190], speed: 0.9, spread: 1.2 }
  if (state === 'speaking') return { color: [255, 255, 255], speed: 0.6, spread: 1 }
  return { color: [242, 239, 233], speed: 0, spread: 1 }
}

/** The tilt toward the viewer, so the constellation reads as a ball rather than a ring. */
const TILT = 0.45

/**
 * Points spread evenly on a unit sphere (a golden-angle spiral), turned
 * about the vertical axis by `angle` and tilted toward the viewer.
 */
export function orbPoints(count: number, angle: number): OrbPoint[] {
  const out: OrbPoint[] = []
  for (let i = 0; i < count; i++) {
    const y0 = 1 - (i / (count - 1)) * 2
    const ring = Math.sqrt(1 - y0 * y0)
    const a = i * 2.39996 + angle
    const x = Math.cos(a) * ring
    const z0 = Math.sin(a) * ring
    out.push({
      x,
      y: y0 * Math.cos(TILT) - z0 * Math.sin(TILT),
      z: y0 * Math.sin(TILT) + z0 * Math.cos(TILT),
    })
  }
  return out
}

/**
 * Which points are joined by the constellation's faint lines: each pair of
 * neighbours on the sphere (closer than `reach`, at most `perPoint` lines
 * from any one point). Turning doesn't change distances, so this is worked
 * out once.
 */
export function orbLinks(points: OrbPoint[], reach = 0.56, perPoint = 3): Array<[number, number]> {
  const links: Array<[number, number]> = []
  const count = new Array<number>(points.length).fill(0)
  for (let i = 0; i < points.length; i++) {
    const near: Array<{ j: number; d: number }> = []
    for (let j = i + 1; j < points.length; j++) {
      const d = Math.hypot(points[i].x - points[j].x, points[i].y - points[j].y, points[i].z - points[j].z)
      if (d < reach) near.push({ j, d })
    }
    near.sort((a, b) => a.d - b.d)
    for (const { j } of near) {
      if (count[i] >= perPoint) break
      if (count[j] >= perPoint) continue
      links.push([i, j])
      count[i] += 1
      count[j] += 1
    }
  }
  return links
}

/** What the orb is told each frame. */
export interface OrbInput {
  state: OrbState
  /** Paused but still on the line, waiting for "Hey Jarvis". */
  waiting: boolean
  /** How loud the voice that matters is right now, 0..1. */
  level: number
  /** A work dot's note is open: the turning eases to a stop so the dot stays put. */
  held?: boolean
}

/** The dots that light up for background work, spread round the shell (the app's `spots`): one per job, up to three. */
export const ORB_WORK_DOTS = [7, 29, 48]

/** The blue of a lit work dot (#4DA3FF), as r, g, b: blue = something Jarvis is working on, orange is kept for things that need Dylan (2026-11-18). */
export const ORB_WORK_BLUE: [number, number, number] = [77, 163, 255]

/** Which dot each job lights: the first three jobs, each on its own fixed dot, so a job keeps its dot while it runs. */
export function orbWorkDots<T>(work: T[]): { task: T; index: number }[] {
  return work.slice(0, ORB_WORK_DOTS.length).map((task, i) => ({ task, index: ORB_WORK_DOTS[i] }))
}

/** How far the shell swells with your voice, as a share of its reach. */
export const ORB_SHELL_SWELL = 0.11

/** Below this the level is room noise and moves nothing. */
const NOISE_FLOOR = 0.08

/** How fast the idle tumble turns, radians a second. */
const TUMBLE_RATE = 0.32

/** True for the states where Jarvis is busy and the shell spins about the vertical. */
function spinsUpright(state: OrbState): boolean {
  return state === 'thinking' || state === 'working' || state === 'speaking'
}

/** Moves `from` toward `to` by the share `k` (0..1). */
function mix(from: number, to: number, k: number): number {
  return from + (to - from) * k
}

/** The share of the way a one-pole filter travels in `dt` seconds with time constant `tau`. */
function glide(dt: number, tau: number): number {
  return 1 - Math.exp(-dt / tau)
}

/**
 * The orb's running state, the same sums as the app's OrbAnimator
 * (ios/App/OrbView.swift; keep the two in step). Stepped once per frame and
 * never reset, so nothing ever cuts (Dylan, 2026-11-17):
 * - the look (colour, reach) eases toward each state's over about 0.75 s;
 * - while you talk the shell holds still and swells as one with your voice;
 * - when nothing is being said (listening in silence, or paused waiting for
 *   "Hey Jarvis") it tumbles slowly about an axis that keeps wandering;
 * - while Jarvis thinks, works or speaks it spins about the vertical, and
 *   his voice moves only the core.
 * Plain idle (no call) still comes to rest: see orbLook.
 */
export class OrbMotion {
  /** The points' colour and reach right now. */
  color: [number, number, number]
  spread: number
  /** The shell's orientation: a rotation matrix (rows), turned a little each frame. */
  private rotation: number[][] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  /** The current angular velocity (x, y, z in radians a second), eased toward each state's. */
  private spin: [number, number, number] = [0, 0, 0]
  /** How recently you were audible (0..1); slow to fall, so gaps between words don't restart the turning. */
  private hearing = 0
  private clock = 0
  /** How much the voice belongs to Jarvis (1) rather than you (0), eased. */
  private speakingMix = 0
  private coreStage = 0
  private coreEnvelope = 0
  private shellStage = 0
  private shellEnvelope = 0
  private readonly base = orbPoints(ORB_POINTS, 0)

  /** Starts already looking like `state`, so the first frame doesn't fade in from another colour. */
  constructor(state: OrbState) {
    const look = orbLook(state)
    this.color = [...look.color]
    this.spread = look.spread
    if (state === 'speaking') this.speakingMix = 1
  }

  /** Your voice, as the shell shows it (0..1). */
  get shellVoice(): number {
    return this.shellEnvelope * (1 - this.speakingMix)
  }

  /** Jarvis's voice, as the core shows it (0..1). */
  get coreVoice(): number {
    return this.coreEnvelope * this.speakingMix
  }

  /** Jumps straight to a state's look with no motion (reduced motion). */
  snap(state: OrbState): void {
    const look = orbLook(state)
    this.color = [...look.color]
    this.spread = look.spread
  }

  /** One frame of `dt` seconds. */
  step(input: OrbInput, dt: number): void {
    const look = orbLook(input.state)
    const ease = glide(dt, 0.75)
    this.color = [mix(this.color[0], look.color[0], ease), mix(this.color[1], look.color[1], ease), mix(this.color[2], look.color[2], ease)]
    this.spread = mix(this.spread, look.spread, ease)
    const speaking = input.state === 'speaking'
    this.speakingMix = mix(this.speakingMix, speaking ? 1 : 0, glide(dt, 0.5))
    this.clock += dt
    this.turn(input, look.speed, dt)

    // Dead zone and soft knee: under the floor is room noise; above it the
    // level rises gently at first.
    const raw = Math.min(Math.max(input.level, 0), 1)
    const gated = Math.max(0, (raw - NOISE_FLOOR) / (1 - NOISE_FLOOR))
    const heard = gated * gated * (3 - 2 * gated)
    // Jarvis's core: two stages, about 85 ms to rise and 280 ms to settle.
    const coreRise = 85 / 1800
    const coreStep = glide(dt, heard > this.coreEnvelope ? coreRise : coreRise * 3.3)
    this.coreStage = mix(this.coreStage, heard, coreStep)
    this.coreEnvelope = mix(this.coreEnvelope, this.coreStage, coreStep)
    // Your shell: lighter smoothing so it follows your syllables (about
    // 50 ms up, 180 ms down), scaled so normal speech uses the whole range,
    // then 30 ms more so one audio chunk can't make it flicker.
    const shellInput = Math.min(1, heard * 1.25)
    const shellRise = 50 / 1800
    this.shellStage = mix(this.shellStage, shellInput, glide(dt, shellInput > this.shellStage ? shellRise : shellRise * 3.6))
    this.shellEnvelope = mix(this.shellEnvelope, this.shellStage, glide(dt, 0.03))
  }

  /** The shell's points where they are now. */
  points(): OrbPoint[] {
    const m = this.rotation
    return this.base.map((p) => ({
      x: m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z,
      y: m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z,
      z: m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z,
    }))
  }

  /**
   * True when nothing is left to move: plain idle, the turning run down,
   * both voices quiet and the look arrived. The drawing loop stops then, so
   * nothing loops forever inside the glass.
   */
  resting(input: OrbInput): boolean {
    if (input.state !== 'idle' || (input.waiting && !input.held)) return false
    if (Math.hypot(...this.spin) > 0.004) return false
    if (this.shellEnvelope > 0.004 || this.coreEnvelope > 0.004) return false
    const look = orbLook('idle')
    const off = Math.abs(this.color[0] - look.color[0]) + Math.abs(this.color[1] - look.color[1]) + Math.abs(this.color[2] - look.color[2])
    return off < 1.5 && Math.abs(this.spread - look.spread) < 0.004
  }

  /** Eases the angular velocity toward what this moment calls for, then turns the shell by it. */
  private turn(input: OrbInput, speed: number, dt: number): void {
    const upright = spinsUpright(input.state)
    // Audible = your voice above the noise floor; rises fast, fades over about 1.2 s.
    const audible = !upright && input.level > NOISE_FLOOR ? 1 : 0
    this.hearing = mix(this.hearing, audible, glide(dt, audible > this.hearing ? 0.08 : 1.2))

    let target: [number, number, number] = [0, 0, 0]
    if (input.held) {
      // A work dot's note is open: hold still so the dot stays under it.
      target = [0, 0, 0]
    } else if (upright) {
      target = [0, speed, 0]
    } else if (input.state === 'listening' || input.waiting) {
      // The idle tumble: an axis drifting smoothly over the sphere.
      const a = this.clock * 0.11
      const b = this.clock * 0.07 + 1.3
      const axis = [Math.sin(a) * Math.cos(b), Math.cos(a) * 0.6 + 0.4, Math.sin(b) * Math.cos(a)]
      const length = Math.max(1e-6, Math.hypot(axis[0], axis[1], axis[2]))
      const rate = TUMBLE_RATE * (1 - this.hearing)
      target = [(axis[0] / length) * rate, (axis[1] / length) * rate, (axis[2] / length) * rate]
    }
    const k = glide(dt, 0.7)
    this.spin = [mix(this.spin[0], target[0], k), mix(this.spin[1], target[1], k), mix(this.spin[2], target[2], k)]

    const rate = Math.hypot(...this.spin)
    if (rate < 1e-6) return
    const angle = rate * dt
    const [x, y, z] = [this.spin[0] / rate, this.spin[1] / rate, this.spin[2] / rate]
    const c = Math.cos(angle)
    const s = Math.sin(angle)
    const t = 1 - c
    // Rodrigues: this frame's small rotation, applied on top of the rest.
    const r = [
      [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
      [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
      [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
    ]
    const m = this.rotation
    const next = r.map((row) => [0, 1, 2].map((j) => row[0] * m[0][j] + row[1] * m[1][j] + row[2] * m[2][j]))
    this.rotation = orthonormal(next)
  }
}

/** Keeps a matrix a pure rotation as tiny rounding errors build up. */
function orthonormal(m: number[][]): number[][] {
  const unit = (v: number[]) => {
    const length = Math.max(1e-9, Math.hypot(v[0], v[1], v[2]))
    return [v[0] / length, v[1] / length, v[2] / length]
  }
  const a = unit(m[0])
  const dot = a[0] * m[1][0] + a[1] * m[1][1] + a[2] * m[1][2]
  const b = unit([m[1][0] - dot * a[0], m[1][1] - dot * a[1], m[1][2] - dot * a[2]])
  const c = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
  return [a, b, c]
}

/** A point's dot: bigger and brighter the nearer it is (radius in px for a given core size, and opacity). */
export function orbDot(point: OrbPoint, core: number): { radius: number; alpha: number } {
  const near = (point.z + 1) / 2
  // Tiny orbs (the Ask bar's 30 px one) keep their dots visible.
  const unit = Math.max(core / 120, 0.35)
  return { radius: (0.7 + near * 1.5) * unit, alpha: 0.18 + near * 0.8 }
}
