import { describe, expect, it } from 'vitest'
import { ORB_POINTS, OrbMotion, orbDot, orbLinks, orbLook, orbPoints, type OrbInput } from '../../src/lib/orb'

/** Steps a motion for `seconds` at 60 frames a second. */
function run(motion: OrbMotion, input: OrbInput, seconds: number) {
  for (let i = 0; i < seconds * 60; i++) motion.step(input, 1 / 60)
}

/** How far the shell's points moved between two snapshots. */
function moved(a: ReturnType<OrbMotion['points']>, b: ReturnType<OrbMotion['points']>): number {
  return Math.max(...a.map((p, i) => Math.hypot(p.x - b[i].x, p.y - b[i].y, p.z - b[i].z)))
}

describe('orb design D', () => {
  it('spreads its points on a unit sphere', () => {
    const points = orbPoints(ORB_POINTS, 0.7)
    expect(points).toHaveLength(ORB_POINTS)
    for (const p of points) expect(Math.hypot(p.x, p.y, p.z)).toBeCloseTo(1, 6)
    // Some behind the glass core, some in front of it.
    expect(points.some((p) => p.z < 0)).toBe(true)
    expect(points.some((p) => p.z >= 0)).toBe(true)
  })

  it('turns: a new angle moves the points', () => {
    expect(orbPoints(10, 0)[3]).not.toEqual(orbPoints(10, 1)[3])
  })

  it('keeps idle still, so nothing loops forever inside glass', () => {
    expect(orbLook('idle').speed).toBe(0)
    for (const state of ['listening', 'thinking', 'working', 'speaking'] as const) {
      expect(orbLook(state).speed).toBeGreaterThan(0)
    }
    expect(orbLook('thinking').speed).toBeGreaterThan(orbLook('listening').speed)
  })

  it('draws near points bigger and brighter', () => {
    const far = orbDot({ x: 0, y: 0, z: -1 }, 120)
    const near = orbDot({ x: 0, y: 0, z: 1 }, 120)
    expect(near.radius).toBeGreaterThan(far.radius)
    expect(near.alpha).toBeGreaterThan(far.alpha)
    // The Ask bar's 30 px orb still shows its dots.
    expect(orbDot({ x: 0, y: 0, z: -1 }, 30).radius).toBeGreaterThan(0.2)
  })

  it('joins neighbouring points with lines, a few from each', () => {
    const points = orbPoints(ORB_POINTS, 0)
    const links = orbLinks(points)
    expect(links.length).toBeGreaterThan(ORB_POINTS)
    const per = new Array(ORB_POINTS).fill(0)
    for (const [i, j] of links) {
      per[i] += 1
      per[j] += 1
      expect(Math.hypot(points[i].x - points[j].x, points[i].y - points[j].y, points[i].z - points[j].z)).toBeLessThan(0.56)
    }
    expect(Math.max(...per)).toBeLessThanOrEqual(3)
  })

  it('swells the shell with your voice and the core with his, never both', () => {
    const yours = new OrbMotion('listening')
    run(yours, { state: 'listening', waiting: false, level: 0.9 }, 1)
    expect(yours.shellVoice).toBeGreaterThan(0.8)
    expect(yours.coreVoice).toBeLessThan(0.01)
    const his = new OrbMotion('speaking')
    run(his, { state: 'speaking', waiting: false, level: 0.9 }, 1)
    expect(his.coreVoice).toBeGreaterThan(0.8)
    expect(his.shellVoice).toBeLessThan(0.01)
  })

  it('ignores room noise', () => {
    const motion = new OrbMotion('listening')
    run(motion, { state: 'listening', waiting: false, level: 0.06 }, 1)
    expect(motion.shellVoice).toBe(0)
  })

  it('holds still while you talk and tumbles in any direction when it is quiet', () => {
    const motion = new OrbMotion('listening')
    const talking: OrbInput = { state: 'listening', waiting: false, level: 0.9 }
    // Long enough for the turning to run down.
    run(motion, talking, 6)
    const before = motion.points()
    run(motion, talking, 1)
    expect(moved(before, motion.points())).toBeLessThan(0.01)
    // Quiet: it turns again, and not just about the vertical (y changes too).
    run(motion, { state: 'listening', waiting: false, level: 0 }, 6)
    const after = motion.points()
    expect(moved(before, after)).toBeGreaterThan(0.2)
    expect(Math.max(...after.map((p, i) => Math.abs(p.y - before[i].y)))).toBeGreaterThan(0.05)
    for (const p of after) expect(Math.hypot(p.x, p.y, p.z)).toBeCloseTo(1, 6)
  })

  it('spins upright while he speaks: heights stay put', () => {
    const motion = new OrbMotion('speaking')
    const before = motion.points()
    run(motion, { state: 'speaking', waiting: false, level: 0 }, 3)
    const after = motion.points()
    expect(moved(before, after)).toBeGreaterThan(0.2)
    expect(Math.max(...after.map((p, i) => Math.abs(p.y - before[i].y)))).toBeLessThan(1e-6)
  })

  it('eases between looks instead of cutting', () => {
    const motion = new OrbMotion('listening')
    const from = orbLook('listening').color[0]
    const to = orbLook('thinking').color[0]
    motion.step({ state: 'thinking', waiting: false, level: 0 }, 1 / 60)
    expect(motion.color[0]).toBeGreaterThan(from)
    expect(motion.color[0]).toBeLessThan(from + (to - from) * 0.1)
    run(motion, { state: 'thinking', waiting: false, level: 0 }, 5)
    expect(motion.color[0]).toBeCloseTo(to, 0)
  })

  it('comes to rest when idle, but keeps tumbling while waiting for "Hey Jarvis"', () => {
    const motion = new OrbMotion('speaking')
    const idle: OrbInput = { state: 'idle', waiting: false, level: 0 }
    run(motion, { state: 'speaking', waiting: false, level: 0.8 }, 1)
    expect(motion.resting(idle)).toBe(false)
    run(motion, idle, 8)
    expect(motion.resting(idle)).toBe(true)
    const waiting: OrbInput = { state: 'idle', waiting: true, level: 0 }
    expect(motion.resting(waiting)).toBe(false)
    const before = motion.points()
    run(motion, waiting, 4)
    expect(moved(before, motion.points())).toBeGreaterThan(0.1)
  })
})
