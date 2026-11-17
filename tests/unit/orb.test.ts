import { describe, expect, it } from 'vitest'
import { ORB_POINTS, orbDot, orbLook, orbPoints } from '../../src/lib/orb'

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
})
