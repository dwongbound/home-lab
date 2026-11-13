// Jarvis's GET /jobs answer, cleaned up for the page by parseJobs.
import { describe, expect, it } from 'vitest'
import { parseJobs } from '../../server/sources/jobs.mjs'

describe('parseJobs', () => {
  it('turns snake_case into the page shape and drops broken rows', () => {
    const out = parseJobs({
      generated_at: '2026-11-13T01:00:00-08:00',
      jobs: [
        { id: 'lookout', name: 'Lookout', group: 'main', model: 'ornith-1.5:9b', schedule: 'Every 30 min', status: 'running', last_run: '2026-11-13T00:50:00-08:00', next_run: 'soon', last_result: ' Checked the drive. ' },
        { id: 'housekeeping-unload', name: 'Model unload', group: 'housekeeping', status: 'weird' },
        { name: 'No id' },
        'junk',
      ],
      lookout: { checks: ['drive_time', 3], watching: [], held_back: [{ text: 'SPY down', reason: 'Normal.' }, { reason: 'no text' }] },
      messenger: { sent_today: 1, cap: 5, quiet: '' },
      running: [
        { id: 'r1', label: ' Making drive times mention parking ', state: 'running', started_at: '2026-11-13T00:58:00-08:00' },
        { id: 'r2', label: 'Saying traffic first', state: 'queued' },
        { id: 'r3', label: 'Odd state', state: 'exploded', started_at: 'not a time' },
        { label: 'no id' },
      ],
    })
    expect(out?.jobs).toEqual([
      { id: 'lookout', name: 'Lookout', group: 'main', model: 'ornith-1.5:9b', schedule: 'Every 30 min', status: 'running', lastRun: '2026-11-13T00:50:00-08:00', nextRun: null, lastResult: 'Checked the drive.' },
      { id: 'housekeeping-unload', name: 'Model unload', group: 'housekeeping', model: null, schedule: null, status: 'ok', lastRun: null, nextRun: null, lastResult: null },
    ])
    expect(out?.lookout).toEqual({ checks: ['drive_time'], watching: [], heldBack: [{ text: 'SPY down', reason: 'Normal.' }] })
    expect(out?.messenger).toEqual({ sentToday: 1, cap: 5, quiet: null })
    // Background work he sent off: trimmed, unknown states read as running, rows without an id dropped.
    expect(out?.running).toEqual([
      { id: 'r1', label: 'Making drive times mention parking', state: 'running', startedAt: '2026-11-13T00:58:00-08:00' },
      { id: 'r2', label: 'Saying traffic first', state: 'queued', startedAt: null },
      { id: 'r3', label: 'Odd state', state: 'running', startedAt: null },
    ])
  })

  it('is null for anything that isn’t a jobs answer', () => {
    expect(parseJobs(null)).toBeNull()
    expect(parseJobs({ jobs: 'no' })).toBeNull()
    expect(parseJobs({ jobs: [] })).toEqual({ generatedAt: null, jobs: [], lookout: null, messenger: null, running: [] })
  })
})
