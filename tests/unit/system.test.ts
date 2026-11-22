import { describe, expect, it } from 'vitest'
import { parseDisks, parseRam, parseSystem } from '../../server/sources/system.mjs'

describe('parseRam', () => {
  it('lists who holds the memory biggest first and names the rest', () => {
    const ram = parseRam({ total_mb: 32000, used_mb: 10000, scope: 'pc', users: [{ name: 'Jarvis', role: 'The agent', mb: 2000 }, { name: ' Windows ', mb: 6000 }, { name: '', mb: 5 }, { name: 'Broken', mb: 'x' }] })
    expect(ram).toEqual({
      totalMb: 32000, usedMb: 10000, scope: 'pc',
      users: [{ name: 'Windows', role: '', mb: 6000 }, { name: 'Jarvis', role: 'The agent', mb: 2000 }, { name: 'Everything else', role: 'Other programs', mb: 2000 }],
    })
  })

  it('never lets the rows add up to more than is used, and treats an unknown scope as Linux only', () => {
    const ram = parseRam({ total_mb: 8000, used_mb: 3000, scope: 'moon', users: [{ name: 'A', mb: 2500 }, { name: 'B', mb: 2000 }, { name: 'C', mb: 100 }] })
    expect(ram?.scope).toBe('linux')
    expect(ram?.users).toEqual([{ name: 'A', role: '', mb: 2500 }, { name: 'B', role: '', mb: 500 }])
  })

  it('is null without totals', () => {
    expect(parseRam(null)).toBeNull()
    expect(parseRam({ total_mb: 0, used_mb: 10 })).toBeNull()
    expect(parseRam({ total_mb: 100 })).toBeNull()
  })
})

describe('parseDisks and parseSystem', () => {
  it('keeps usable disks with their folders and drops broken ones', () => {
    const disks = parseDisks([
      { id: 'c', name: 'C: drive', used_gb: 216.04, total_gb: 238, users: [{ name: 'Linux disk', gb: 92 }, { name: 'Windows', gb: 61.26 }, { gb: 3 }] },
      { id: 'bad id!', name: 'X', used_gb: 1, total_gb: 2 },
      { id: 'd', name: 'D:', used_gb: 5 },
    ])
    expect(disks).toEqual([{ id: 'c', name: 'C: drive', usedGb: 216, totalGb: 238, users: [{ name: 'Linux disk', gb: 92 }, { name: 'Windows', gb: 61.3 }, { name: 'Everything else', gb: 62.7 }] }])
    expect(parseDisks('x')).toBeNull()
    expect(parseDisks([{ id: 'd' }])).toBeNull()
  })

  it('gives each half on its own, null when Jarvis leaves it out', () => {
    expect(parseSystem({ ram: { total_mb: 100, used_mb: 50 } })).toEqual({ ram: { totalMb: 100, usedMb: 50, scope: 'linux', users: [] }, disks: null })
    expect(parseSystem(undefined)).toEqual({ ram: null, disks: null })
  })
})
