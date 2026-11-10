import type { CalendarEvent, Snapshot, TimelineItem } from '../types'
import { clock } from '../lib/format'
import { todayAgenda } from '../lib/agenda'
import { closeDetail, parseDetail, useHashDetail } from '../useHashView'
import { DetailDialog, type Fact, type OutLink } from './DetailDialog'

// The pop-ups behind Today, the calendar and email rows on Overview and
// Schedule: #overview/j/<row id>, #schedule/e/<event id>, #schedule/m/<email id>.
// Links out to Google Calendar or Gmail show when the digest has them.

const STATUS_WORDS = { done: 'Done', failed: 'Needs you', running: 'Happening now', scheduled: 'Later today' } as const

/** "3:00 PM to 5:00 PM", or "All day". */
function eventWhen(e: CalendarEvent): string {
  if (e.allDay) return 'All day'
  return `${clock(e.start)} to ${clock(e.end)}`
}

/** The pop-up for a calendar event. */
function EventDetail({ e }: { e: CalendarEvent }) {
  const facts: Fact[] = [
    { label: 'When', value: eventWhen(e) },
    { label: 'Calendar', value: e.calendar },
  ]
  if (e.location) facts.push({ label: 'Where', value: e.location })
  const links: OutLink[] = []
  if (e.url) links.push({ label: 'Open in Calendar', href: e.url })
  return <DetailDialog title={e.title} sub={eventWhen(e)} facts={facts} links={links} onClose={closeDetail} />
}

/** The pop-up for a Today row that isn't a calendar event: a Jarvis job or reminder, or an alert. */
function ItemDetail({ item }: { item: TimelineItem }) {
  const facts: Fact[] = [{ label: 'Status', value: STATUS_WORDS[item.status] }]
  if (item.source === 'alert') {
    facts.push({ label: 'What to do', value: <a href="#services">See it on Services</a> })
  } else {
    facts.unshift({ label: 'When', value: clock(item.at) })
    facts.push({ label: 'From', value: 'Jarvis' })
  }
  return <DetailDialog title={item.title} sub={item.detail} facts={facts} onClose={closeDetail} />
}

/** Whichever agenda detail the hash names, or nothing. */
export function AgendaDetail({ data, now }: { data: Snapshot; now: Date }) {
  const detail = useHashDetail()
  if (detail === '') return null
  const { kind, id } = parseDetail(detail)
  const events = data.cloud?.calendar ?? []
  if (kind === 'e') {
    const e = events.find((x) => x.id === id)
    if (e) return <EventDetail key={detail} e={e} />
  }
  if (kind === 'm') {
    const m = (data.cloud?.email ?? []).find((x) => x.id === id)
    if (m) {
      const links: OutLink[] = []
      if (m.url) links.push({ label: 'Open in Gmail', href: m.url })
      return <DetailDialog key={detail} title={m.subject} sub={m.from} facts={[{ label: 'Why', value: m.why }]} links={links} onClose={closeDetail} />
    }
  }
  if (kind === 'j') {
    // Calendar rows on Today carry "cal-" before the event's own id (lib/agenda.ts).
    const e = events.find((x) => `cal-${x.id}` === id)
    if (e) return <EventDetail key={detail} e={e} />
    const item = todayAgenda(data, now).find((x) => x.id === id)
    if (item) return <ItemDetail key={detail} item={item} />
  }
  return null
}
