import type { GpuUse, GpuUser } from '../types'

// The plain sums behind the graphics card pie chart: each holder's share of
// the whole card, where its slice starts, and its colour. The free part is
// the last slice.

/** One slice of the pie: a holder of memory, or the free remainder. */
export interface GpuSlice {
  name: string
  role: string
  mb: number
  /** Share of the whole card, 0 to 1. */
  share: number
  /** Where the slice starts around the ring, 0 to 1 from the top, clockwise. */
  start: number
  /** A CSS colour. */
  color: string
  free: boolean
}

/** Local models are warm, speech models cool, so the two groups read apart at a glance. */
const LOCAL_COLORS = ['var(--ember)', '#f0919a']
const SPEECH_COLORS = ['var(--glacier)', 'var(--moss)', '#b9a6f0', '#7fd4d0']
const OTHER_COLOR = 'rgba(242, 239, 233, 0.45)'
const FREE_COLOR = 'rgba(255, 255, 255, 0.1)'

/** The colour for the nth holder of its kind; a kind's colours repeat if there are more holders than colours. */
function colorFor(user: GpuUser, nth: number): string {
  if (user.kind === 'local') return LOCAL_COLORS[nth % LOCAL_COLORS.length]
  if (user.kind === 'speech') return SPEECH_COLORS[nth % SPEECH_COLORS.length]
  return OTHER_COLOR
}

/** Megabytes as "6.4 GB", or "420 MB" under a tenth of a gigabyte short of one. */
export function memoryText(mb: number): string {
  if (mb < 1000) return `${Math.round(mb)} MB`
  return `${Math.round(mb / 102.4) / 10} GB`
}

/** Every slice of the pie in order: the holders as given (biggest first), then what's free. */
export function gpuSlices(gpu: GpuUse): GpuSlice[] {
  const slices: GpuSlice[] = []
  const seen = { local: 0, speech: 0, other: 0 }
  let start = 0
  for (const user of gpu.users) {
    const share = Math.min(user.mb / gpu.totalMb, 1 - start)
    slices.push({ name: user.name, role: user.role, mb: user.mb, share, start, color: colorFor(user, seen[user.kind]), free: false })
    seen[user.kind] += 1
    start += share
  }
  const freeMb = Math.max(0, gpu.totalMb - gpu.usedMb)
  slices.push({ name: 'Free', role: 'Room for more', mb: freeMb, share: Math.max(0, 1 - start), start, color: FREE_COLOR, free: true })
  return slices
}

/** The line under the title: "10.1 GB of 12 GB in use · 34% busy". */
export function gpuSummary(gpu: GpuUse): string {
  const used = `${memoryText(gpu.usedMb)} of ${memoryText(gpu.totalMb)} in use`
  if (gpu.utilization === null) return used
  return `${used} · ${gpu.utilization}% busy`
}
