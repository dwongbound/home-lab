// The graphics card pie: the server's sums (who holds what), the page's
// slices, and the panel itself.
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { buildGpu, ollamaRows, parseJarvisGpu, parseSmi } from '../../server/sources/gpu.mjs'
import { gpuSlices, gpuSummary, memoryText } from '../../src/lib/gpu'
import { GpuPie } from '../../src/components/GpuPie'
import type { GpuUse } from '../../src/types'

const gpu: GpuUse = {
  totalMb: 12288,
  usedMb: 10240,
  utilization: 34,
  users: [
    { name: 'Ornith', role: 'Local brain', mb: 6144, kind: 'local' },
    { name: 'Parakeet', role: 'Hears you', mb: 3072, kind: 'speech' },
    { name: 'Everything else', role: 'Windows, the desktop and drivers', mb: 1024, kind: 'other' },
  ],
}

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

describe('gpuSlices', () => {
  it('gives each holder its share and ends with what is free', () => {
    const slices = gpuSlices(gpu)
    expect(slices.map((slice) => slice.name)).toEqual(['Ornith', 'Parakeet', 'Everything else', 'Free'])
    expect(slices[0].share).toBe(0.5)
    expect(slices[2].share).toBeCloseTo(1 / 12)
    expect(slices[3].share).toBeCloseTo(1 / 6)
    expect(slices[1].start).toBe(0.5)
    expect(slices[3]).toMatchObject({ mb: 2048, free: true })
    // Local and speech models get different colours.
    expect(slices[0].color).not.toBe(slices[1].color)
  })

  it('writes sizes and the summary in plain words', () => {
    expect(memoryText(6554)).toBe('6.4 GB')
    expect(memoryText(420)).toBe('420 MB')
    expect(gpuSummary(gpu)).toBe('10 GB of 12 GB in use · 34% busy')
    expect(gpuSummary({ ...gpu, utilization: null })).toBe('10 GB of 12 GB in use')
  })
})

describe('GpuPie', () => {
  it('lists every holder with its size, and what is free', () => {
    render(<GpuPie gpu={gpu} />)
    expect(screen.getByRole('heading', { name: 'Graphics card' })).toBeTruthy()
    expect(screen.getByText('Ornith')).toBeTruthy()
    expect(screen.getByText('Hears you')).toBeTruthy()
    expect(screen.getByText('Free')).toBeTruthy()
    expect(document.querySelectorAll('.gpu__ring circle')).toHaveLength(4)
  })

  it('says so when the card is not reporting', () => {
    render(<GpuPie gpu={null} />)
    expect(screen.getByText(/isn.t reporting/)).toBeTruthy()
  })
})
