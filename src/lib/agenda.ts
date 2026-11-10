import type { CalendarEvent, RunStatus, Snapshot, TimelineItem } from '../types'
import { clock } from './format'

// The Overview's "Today": Dylan's calendar, Jarvis's reminders and jobs, and
// anything on jarvis that needs him right now, in one list. Alerts come
// first, then all-day events, then everything else by time.

/** Done once it has ended, "now" while it's on, otherwise later today. */
function eventStatus(e: CalendarEvent, now: Date): RunStatus {
  if (e.allDay) return 'scheduled'
  const t = now.getTime()
  if (Date.parse(e.end) <= t) return 'done'
  if (Date.parse(e.start) <= t) return 'running'
  return 'scheduled'
}

/** One calendar event as a timeline row. */
function fromEvent(e: CalendarEvent, now: Date): TimelineItem {
  let detail = `Until ${clock(e.end)} · ${e.calendar}`
  if (e.allDay) detail = e.calendar
  return { id: `cal-${e.id}`, at: e.start, title: e.title, detail, status: eventStatus(e, now), source: 'calendar', allDay: e.allDay }
}

/** Services not running right, as alert rows stamped with the snapshot's time. */
function serviceAlerts(s: Snapshot): TimelineItem[] {
  const alerts: TimelineItem[] = []
  for (const sv of s.services) {
    if (sv.status !== 'degraded' && sv.status !== 'down') continue
    alerts.push({ id: `alert-${sv.id}`, at: s.generatedAt, title: `${sv.name}: ${sv.detail}`, detail: 'Needs you', status: 'failed', source: 'alert' })
  }
  return alerts
}

/** Sort order: alerts, then all-day events, then by time. */
function rank(it: TimelineItem): number {
  if (it.source === 'alert') return 0
  if (it.allDay) return 1
  return 2
}

/** Today's calendar, Jarvis's schedule and alerts, merged and sorted. */
export function todayAgenda(s: Snapshot, now: Date): TimelineItem[] {
  const items: TimelineItem[] = [...serviceAlerts(s)]
  for (const t of s.today) items.push({ ...t, source: t.source ?? 'jarvis' })
  if (s.cloud !== null) {
    for (const e of s.cloud.calendar) items.push(fromEvent(e, now))
  }
  return items.toSorted((a, b) => rank(a) - rank(b) || a.at.localeCompare(b.at))
}
