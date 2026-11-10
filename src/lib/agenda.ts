import type { CalendarEvent, RunStatus, Snapshot, TimelineItem } from '../types'
import { clock } from './format'

// The Overview's "Today": Dylan's calendar and Jarvis's reminders and jobs
// in one list, all-day events first, then everything else by time.
// Anything needing him right now (a service down) isn't part of the day:
// it's a banner across the top of every page (activeAlerts, AlertBanner).

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

export interface ActiveAlert { id: string; text: string }

/** Services not running right, for the banner. */
export function activeAlerts(s: Snapshot): ActiveAlert[] {
  const alerts: ActiveAlert[] = []
  for (const sv of s.services) {
    if (sv.status !== 'degraded' && sv.status !== 'down') continue
    alerts.push({ id: sv.id, text: `${sv.name}: ${sv.detail}` })
  }
  return alerts
}

/** Sort order: all-day events, then by time. */
function rank(it: TimelineItem): number {
  if (it.allDay) return 0
  return 1
}

/** Today's calendar and Jarvis's schedule, merged and sorted. */
export function todayAgenda(s: Snapshot, now: Date): TimelineItem[] {
  const items: TimelineItem[] = []
  for (const t of s.today) items.push({ ...t, source: t.source ?? 'jarvis' })
  if (s.cloud !== null) {
    for (const e of s.cloud.calendar) items.push(fromEvent(e, now))
  }
  return items.toSorted((a, b) => rank(a) - rank(b) || a.at.localeCompare(b.at))
}
