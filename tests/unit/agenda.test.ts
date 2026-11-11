// The Overview's combined day (calendar and Jarvis in one order), and the
// alerts that go in the banner instead.
import { describe, expect, it } from 'vitest'
import { activeAlerts, todayAgenda } from '../../src/lib/agenda'
import type { Snapshot } from '../../src/types'

const NOW = new Date('2026-11-10T20:00:00Z')

/** A snapshot with just the parts the agenda reads. */
function snap(parts: Partial<Snapshot>): Snapshot {
  return { generatedAt: NOW.toISOString(), services: [], today: [], cloud: null, moneyPicks: { picks: [], remindAt: null }, ...parts } as unknown as Snapshot
}

const cloud = (calendar: unknown[]) => ({ updatedAt: NOW.toISOString(), threads: [], calendar, email: [], deploys: [], pullRequests: [] })

describe('todayAgenda', () => {
  it('puts all-day events first, then calendar and Jarvis by time, and leaves alerts out', () => {
    const items = todayAgenda(snap({
      services: [{ id: 'jarvis', name: 'Jarvis', detail: 'Not answering', status: 'down' }, { id: 'ha', name: 'HA', detail: 'ok', status: 'up' }] as Snapshot['services'],
      today: [{ id: 'j1', at: '2026-11-10T17:00:00Z', title: 'Fantasy pickups', detail: 'Jarvis', status: 'done' }],
      cloud: cloud([
        { id: 'c1', title: 'Flight block', start: '2026-11-10T23:00:00Z', end: '2026-11-11T01:00:00Z', allDay: false, calendar: 'VFF' },
        { id: 'c2', title: 'Anniversary', start: '2026-11-10T08:00:00Z', end: '2026-11-11T08:00:00Z', allDay: true, calendar: 'Personal' },
        { id: 'c3', title: 'Standup', start: '2026-11-10T19:30:00Z', end: '2026-11-10T20:15:00Z', allDay: false, calendar: 'Work' },
      ]) as Snapshot['cloud'],
    }), NOW)
    expect(items.map((i) => i.title)).toEqual(['Anniversary', 'Fantasy pickups', 'Standup', 'Flight block'])
    expect(items.map((i) => i.source)).toEqual(['calendar', 'jarvis', 'calendar', 'calendar'])
    // Standup is on now, the flight is later.
    expect(items[2].status).toBe('running')
    expect(items[3].status).toBe('scheduled')
    expect(items[0].allDay).toBe(true)
  })

  it('lists services that are down or degraded as alerts for the banner', () => {
    const alerts = activeAlerts(snap({
      services: [
        { id: 'jarvis', name: 'Jarvis', detail: 'Not answering', status: 'down' },
        { id: 'ha', name: 'HA', detail: 'ok', status: 'up' },
        { id: 'ollama', name: 'Ollama', detail: 'Slow', status: 'degraded' },
      ] as Snapshot['services'],
    }))
    expect(alerts).toEqual([{ id: 'jarvis', text: 'Jarvis: Not answering', href: '#services' }, { id: 'ollama', text: 'Ollama: Slow', href: '#services' }])
  })

  it('reminds about Money picks once their time comes, ahead of services', () => {
    const pick = { id: 'x5', category: 'Lessons', merchant: 'Venmo Alex', date: '2026-11-09T00:00:00Z', amount: 120, pickedAt: '2026-11-09T01:00:00Z' }
    const services = [{ id: 'jarvis', name: 'Jarvis', detail: 'Not answering', status: 'down' }] as Snapshot['services']
    const later = snap({ services, moneyPicks: { picks: [pick], remindAt: '2026-11-11T04:00:00Z' } })
    expect(activeAlerts(later, NOW).map((a) => a.id)).toEqual(['jarvis'])
    const due = snap({ services, moneyPicks: { picks: [pick, { ...pick, id: 'x6' }], remindAt: '2026-11-10T19:00:00Z' } })
    expect(activeAlerts(due, NOW)[0]).toEqual({ id: 'money-picks', text: '2 purchases ready to recategorize in Copilot', href: '#money/ready' })
  })

  it('marks a finished event done, and has only Jarvis without a digest', () => {
    const done = todayAgenda(snap({ cloud: cloud([{ id: 'c', title: 'Coffee', start: '2026-11-10T16:00:00Z', end: '2026-11-10T17:00:00Z', allDay: false, calendar: 'Me' }]) as Snapshot['cloud'] }), NOW)
    expect(done[0].status).toBe('done')
    expect(todayAgenda(snap({}), NOW)).toEqual([])
  })
})
