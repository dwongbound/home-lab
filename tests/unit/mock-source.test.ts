// The mock source: Pacific times, the week's bars, and the local model toggle.
import { describe, expect, it } from 'vitest'
import { atPacificTime, createMockSource } from '../../server/sources/mock.mjs'

/** "9:00 AM" style time of an ISO string, on the PC's (Pacific) clock. */
function pacificClock(iso: string): string {
  return new Intl.DateTimeFormat('en-US', { timeZone: 'America/Los_Angeles', hour: 'numeric', minute: '2-digit' }).format(new Date(iso))
}

describe('atPacificTime', () => {
  it('lands on the Pacific wall-clock time in summer and winter', () => {
    // 2026-11-06 10:00 UTC is 2 am Pacific (PST, after the Nov 1 change).
    expect(pacificClock(atPacificTime(new Date('2026-11-06T10:00:00Z'), 9, 0))).toBe('9:00 AM')
    // July is PDT.
    expect(pacificClock(atPacificTime(new Date('2026-07-01T20:00:00Z'), 17, 5))).toBe('5:05 PM')
  })
  it('stays on the Pacific calendar day even when UTC has rolled over', () => {
    // 2026-11-07 03:00 UTC is still Nov 6 in LA.
    const iso = atPacificTime(new Date('2026-11-07T03:00:00Z'), 9, 0)
    expect(iso).toBe('2026-11-06T17:00:00.000Z')
  })
})

describe('createMockSource', () => {
  // Friday 6 Nov 2026, 10 am Pacific.
  const now = () => new Date('2026-11-06T18:00:00Z')

  it('marks today and zeroes the days still to come', async () => {
    const snap = await createMockSource({ now }).snapshot()
    const today = snap.requests.find((d: { today: boolean }) => d.today)!
    expect(today.day).toBe('Fri')
    expect(snap.requests.find((d: { day: string }) => d.day === 'Sat')!.count).toBe(0)
  })

  it('has the same services as the live source, without Open WebUI', async () => {
    const snap = await createMockSource({ now }).snapshot()
    expect(snap.services.map((s: { id: string }) => s.id)).toEqual(['ha', 'ollama', 'jarvis'])
  })

  it('keeps activity newest first', async () => {
    const snap = await createMockSource({ now }).snapshot()
    const times = snap.activity.map((a: { at: string }) => a.at)
    expect(times).toEqual([...times].sort().reverse())
  })

  it('unloading the local model frees its GPU memory and leaves nothing loaded', async () => {
    const source = createMockSource({ now })
    expect((await source.snapshot()).models.map((m: { name: string; role: string }) => [m.name, m.role])).toEqual([['ornith-1.5:9b', 'watch']])
    const result = await source.action('ollama-unload')
    expect(result).toEqual({ ok: true, message: 'Local model unloaded' })
    const snap = await source.snapshot()
    expect(snap.model).toMatchObject({ name: 'ornith-1.5:9b', loaded: false })
    expect(snap.services.find((s: { id: string }) => s.id === 'ollama')!.detail).toBe('No model loaded')
    expect(snap.models).toEqual([])
  })

  it('answers Ask Jarvis with a sample reply', async () => {
    const result = await createMockSource().ask('hello')
    expect(result.ok).toBe(true)
    expect(result.message).toContain('"hello"')
  })

  it('refuses unknown actions', async () => {
    const result = await createMockSource({ now }).action('format-c')
    expect(result).toEqual({ ok: false, message: 'Unknown action: format-c' })
  })
})
