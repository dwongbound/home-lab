// The Overview's combined day: calendar, Jarvis and alerts in one order.
import { describe, expect, it } from 'vitest'
import { todayAgenda } from '../../src/lib/agenda'
import type { Snapshot } from '../../src/types'

const NOW = new Date('2026-11-10T20:00:00Z')

/** A snapshot with just the parts the agenda reads. */
function snap(parts: Partial<Snapshot>): Snapshot {
  return { generatedAt: NOW.toISOString(), services: [], today: [], cloud: null, ...parts } as unknown as Snapshot
}

const cloud = (calendar: unknown[]) => ({ updatedAt: NOW.toISOString(), threads: [], calendar, email: [], deploys: [], pullRequests: [] })

describe('todayAgenda', () => {
  it('puts alerts first, then all-day events, then calendar and Jarvis by time', () => {
    const items = todayAgenda(snap({
      services: [{ id: 'jarvis', name: 'Jarvis', detail: 'Not answering', status: 'down' }, { id: 'ha', name: 'HA', detail: 'ok', status: 'up' }] as Snapshot['services'],
      today: [{ id: 'j1', at: '2026-11-10T17:00:00Z', title: 'Fantasy pickups', detail: 'Jarvis', status: 'done' }],
      cloud: cloud([
        { id: 'c1', title: 'Flight block', start: '2026-11-10T23:00:00Z', end: '2026-11-11T01:00:00Z', allDay: false, calendar: 'VFF' },
        { id: 'c2', title: 'Anniversary', start: '2026-11-10T08:00:00Z', end: '2026-11-11T08:00:00Z', allDay: true, calendar: 'Personal' },
        { id: 'c3', title: 'Standup', start: '2026-11-10T19:30:00Z', end: '2026-11-10T20:15:00Z', allDay: false, calendar: 'Work' },
      ]) as Snapshot['cloud'],
    }), NOW)
    expect(items.map((i) => i.title)).toEqual(['Jarvis: Not answering', 'Anniversary', 'Fantasy pickups', 'Standup', 'Flight block'])
    expect(items.map((i) => i.source)).toEqual(['alert', 'calendar', 'jarvis', 'calendar', 'calendar'])
    // Standup is on now, the flight is later.
    expect(items[3].status).toBe('running')
    expect(items[4].status).toBe('scheduled')
    expect(items[1].allDay).toBe(true)
  })

  it('marks a finished event done, and has only Jarvis without a digest', () => {
    const done = todayAgenda(snap({ cloud: cloud([{ id: 'c', title: 'Coffee', start: '2026-11-10T16:00:00Z', end: '2026-11-10T17:00:00Z', allDay: false, calendar: 'Me' }]) as Snapshot['cloud'] }), NOW)
    expect(done[0].status).toBe('done')
    expect(todayAgenda(snap({}), NOW)).toEqual([])
  })
})
