import { pickReminderDue } from './money'
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

/** Something for the banner, and where tapping it goes. */
export interface ActiveAlert { id: string; text: string; href: string }

/** The banner warns when C: has this many GB free or fewer (Dylan, 2026-11-18). Jarvis pushes at the same mark. */
export const LOW_DISK_GB = 7

/**
 * For the banner: Money page picks whose reminder has come (Dylan asked to
 * be reminded to apply them in Copilot), a nearly full disk, then services
 * not running right.
 */
export function activeAlerts(s: Snapshot, now: Date = new Date()): ActiveAlert[] {
  const alerts: ActiveAlert[] = []
  if (pickReminderDue(s.moneyPicks, now)) {
    const n = s.moneyPicks.picks.length
    let text = `${n} purchases ready to recategorize in Copilot`
    if (n === 1) text = 'One purchase ready to recategorize in Copilot'
    alerts.push({ id: 'money-picks', text, href: '#money/ready' })
  }
  const disk = s.metrics.find((m) => m.id === 'disk')
  if (disk && disk.value !== null && disk.value <= LOW_DISK_GB) {
    alerts.push({ id: 'disk-low', text: `Disk space low: ${disk.value} GB free on C:`, href: '#overview' })
  }
  for (const sv of s.services) {
    if (sv.status !== 'degraded' && sv.status !== 'down') continue
    alerts.push({ id: sv.id, text: `${sv.name}: ${sv.detail}`, href: '#services' })
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
