// The backdrop's time-of-day phases and the sparkline path builder.
import { describe, expect, it } from 'vitest'
import { skyPhase } from '../../src/lib/sky'
import { sparkPath } from '../../src/lib/sparkline'

/** A Date at local h:m today. */
function at(h: number, m = 0): Date {
  const d = new Date()
  d.setHours(h, m, 0, 0)
  return d
}

describe('skyPhase', () => {
  it('changes at the documented times', () => {
    expect(skyPhase(at(5, 29))).toBe('night')
    expect(skyPhase(at(5, 30))).toBe('dawn')
    expect(skyPhase(at(8))).toBe('day')
    expect(skyPhase(at(16, 30))).toBe('dusk')
    expect(skyPhase(at(20))).toBe('night')
  })
})

describe('sparkPath', () => {
  it('is empty with fewer than two points', () => {
    expect(sparkPath([], 120, 40)).toBe('')
    expect(sparkPath([3], 120, 40)).toBe('')
  })
  it('spans the box, lowest value at the bottom', () => {
    expect(sparkPath([0, 10], 120, 40, 2)).toBe('M2.0 38.0L118.0 2.0')
  })
  it('draws a flat line for constant values instead of dividing by zero', () => {
    expect(sparkPath([5, 5, 5], 100, 20, 0)).toBe('M0.0 20.0L50.0 20.0L100.0 20.0')
  })
})
