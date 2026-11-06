// Text helpers: greeting, uptime, "x ago", share.
import { describe, expect, it } from 'vitest'
import { ago, greeting, share, uptime } from '../../src/lib/format'

/** A Date at the given local hour today. */
function atHour(h: number): Date {
  const d = new Date()
  d.setHours(h, 0, 0, 0)
  return d
}

describe('greeting', () => {
  it('follows the hour', () => {
    expect(greeting(atHour(2))).toBe('Still up')
    expect(greeting(atHour(9))).toBe('Good morning')
    expect(greeting(atHour(13))).toBe('Good afternoon')
    expect(greeting(atHour(19))).toBe('Good evening')
  })
})

describe('uptime', () => {
  it('uses days once past a day', () => {
    expect(uptime(6 * 86400 + 4 * 3600)).toBe('6 days, 4 h')
    expect(uptime(86400)).toBe('1 day, 0 h')
  })
  it('uses hours and minutes under a day', () => {
    expect(uptime(3 * 3600 + 12 * 60)).toBe('3 h 12 min')
    expect(uptime(8 * 60)).toBe('8 min')
  })
})

describe('ago', () => {
  const now = new Date('2026-11-06T18:00:00Z')
  it('reads naturally', () => {
    expect(ago('2026-11-06T18:00:00Z', now)).toBe('just now')
    expect(ago('2026-11-06T17:56:00Z', now)).toBe('4 min ago')
    expect(ago('2026-11-06T16:00:00Z', now)).toBe('2 h ago')
    expect(ago('2026-11-05T18:00:00Z', now)).toBe('1 day ago')
  })
})

describe('share', () => {
  it('clamps and handles unknowns', () => {
    expect(share(8, 16)).toBe(0.5)
    expect(share(20, 16)).toBe(1)
    expect(share(null, 16)).toBeNull()
    expect(share(4, 0)).toBeNull()
  })
})
