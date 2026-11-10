import { memo } from 'react'
import type { RunStatus, TimelineItem } from '../types'
import { clock } from '../lib/format'

// A day as a list, each row with a coloured edge for its state (done,
// failed, now, later). The Schedule page shows Jarvis's runs with it; the
// Overview shows the combined day from lib/agenda.ts, already sorted.

const STATUS: Record<RunStatus, string> = { done: 'Done', failed: 'Failed', running: 'Now', scheduled: 'Later' }

/** Where a row came from, as the small word under its title. */
const SOURCE = { calendar: 'Calendar', jarvis: 'Jarvis', alert: 'Alert' } as const

interface TimelineProps {
  items: TimelineItem[]
  now: Date
  title?: string
  /** Show at most this many rows. */
  limit?: number
  /** Leave out what's already done, for a glance at what's left. */
  upcoming?: boolean
  /** Keep the order given instead of sorting by time. */
  presorted?: boolean
  /** What to say when there's nothing to show. */
  empty?: string
  /** A short status after the date, like "Updating from Jarvis…". */
  note?: string
  /** Where tapping a row goes (its detail pop-up); rows aren't links without it. */
  linkTo?: (item: TimelineItem) => string
}

/** The time column: the clock time, or "All day". */
function RowTime({ item }: { item: TimelineItem }) {
  if (item.allDay) return <span className="timeline__time">All day</span>
  return <time className="timeline__time" dateTime={item.at}>{clock(item.at)}</time>
}

/** A row's card, as a link to its detail when there is one. */
function RowCard({ item, href }: { item: TimelineItem; href?: string }) {
  const inside = (
    <>
      <span className="timeline__title">{item.title}</span>
      <span className="timeline__detail">{item.detail}</span>
      {item.source ? <span className="timeline__source">{SOURCE[item.source]}</span> : null}
      <span className="badge" data-status={item.status}>{STATUS[item.status]}</span>
    </>
  )
  if (href) return <a className="timeline__card timeline__card--link" href={href}>{inside}</a>
  return <div className="timeline__card">{inside}</div>
}

/** The timeline panel. */
export const Timeline = memo(function Timeline({ items, now, title = 'Today', limit, upcoming = false, presorted = false, empty = 'Nothing scheduled on jarvis today.', note, linkTo }: TimelineProps) {
  const dateLabel = new Intl.DateTimeFormat('en-US', { weekday: 'long', month: 'short', day: 'numeric' }).format(now)
  let rows = items
  if (!presorted) rows = items.toSorted((a, b) => a.at.localeCompare(b.at))
  if (upcoming) rows = rows.filter((it) => it.status !== 'done')
  const shown = limit ? rows.slice(0, limit) : rows
  return (
    <section className="glass panel timeline" aria-labelledby="today-title">
      <header className="panel__head">
        <div>
          <h2 id="today-title" className="panel__title">{title}</h2>
          <p className="panel__sub">
            {dateLabel}
            {note ? <span className="updating" role="status"> · {note}</span> : null}
          </p>
        </div>
      </header>
      {shown.length === 0 ? (
        <p className="empty">{empty}</p>
      ) : (
        <ol className="timeline__list">
          {shown.map((it) => (
            <li key={it.id} className="timeline__item" data-status={it.status} data-source={it.source}>
              <RowTime item={it} />
              <RowCard item={it} href={linkTo?.(it)} />
            </li>
          ))}
        </ol>
      )}
    </section>
  )
})
