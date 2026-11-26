// The graphics card: the server's sums of who holds its memory.
import { describe, expect, it } from 'vitest'
import { buildGpu, ollamaRows, parseJarvisGpu, parseSmi } from '../../server/sources/gpu.mjs'

describe('parseSmi', () => {
  it('reads used, total and how busy the card is', () => {
    expect(parseSmi('10342, 12288, 37\n')).toEqual({ usedMb: 10342, totalMb: 12288, utilization: 37 })
    expect(parseSmi('10342, 12288, [N/A]\n')).toEqual({ usedMb: 10342, totalMb: 12288, utilization: null })
    expect(parseSmi('10342, 12288\n')?.utilization).toBeNull()
    expect(parseSmi('No devices were found')).toBeNull()
  })
})

describe('parseJarvisGpu', () => {
  it('keeps loaded models with a name and a size', () => {
    const rows = parseJarvisGpu({ models: [{ name: 'Parakeet', role: 'Hears you', mb: 2430.4, loaded: true }, { name: 'Qwen3-ASR', mb: 4600, loaded: false }, { name: 'Kokoro', mb: 900, loaded: true }, { mb: 5, loaded: true }, { name: 'Zero', mb: 0, loaded: true }] })
    expect(rows).toEqual([{ name: 'Parakeet', role: 'Hears you', mb: 2430, kind: 'speech' }, { name: 'Kokoro', role: 'Speech model', mb: 900, kind: 'speech' }])
    expect(parseJarvisGpu(null)).toEqual([])
    expect(parseJarvisGpu({ models: 'none' })).toEqual([])
  })
})

describe('ollamaRows', () => {
  it('names each model by its family and leaves out ones not on the card', () => {
    const rows = ollamaRows([{ name: 'ornith-1.5:9b', size_vram: 6000 * 1024 ** 2 }, { name: 'gemma3:4b', size_vram: 3000 * 1024 ** 2 }, { name: 'cpu-only:1b', size_vram: 0 }], 'ornith-1.5:9b')
    expect(rows).toEqual([{ name: 'Ornith', role: 'Local brain', mb: 6000, kind: 'local' }, { name: 'Gemma3', role: 'Local model', mb: 3000, kind: 'local' }])
  })
})

describe('buildGpu', () => {
  it('sorts biggest first and adds the unnamed rest', () => {
    const built = buildGpu({ usedMb: 4000, totalMb: 12288, utilization: 5 }, [{ name: 'Kokoro', role: 'His voice', mb: 900, kind: 'speech' }, { name: 'Parakeet', role: 'Hears you', mb: 2430, kind: 'speech' }])
    expect(built?.users.map((user: { name: string; mb: number }) => [user.name, user.mb])).toEqual([['Parakeet', 2430], ['Kokoro', 900], ['Everything else', 670]])
  })

  it('never names more than is in use, and skips a tiny leftover', () => {
    const built = buildGpu({ usedMb: 3000, totalMb: 12288, utilization: null }, [{ name: 'A', role: 'x', mb: 2990, kind: 'local' }, { name: 'B', role: 'x', mb: 500, kind: 'speech' }, { name: 'C', role: 'x', mb: 100, kind: 'speech' }])
    expect(built?.users).toEqual([{ name: 'A', role: 'x', mb: 2990, kind: 'local' }, { name: 'B', role: 'x', mb: 10, kind: 'speech' }])
    expect(buildGpu(null, [])).toBeNull()
  })
})
