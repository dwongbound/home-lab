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
}

/** The time column: the clock time, or "All day". */
function RowTime({ item }: { item: TimelineItem }) {
  if (item.allDay) return <span className="timeline__time">All day</span>
  return <time className="timeline__time" dateTime={item.at}>{clock(item.at)}</time>
}

/** The timeline panel. */
export const Timeline = memo(function Timeline({ items, now, title = 'Today', limit, upcoming = false, presorted = false, empty = 'Nothing scheduled on jarvis today.', note }: TimelineProps) {
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
              <div className="timeline__card">
                <p className="timeline__title">{it.title}</p>
                <p className="timeline__detail">{it.detail}</p>
                {it.source ? <span className="timeline__source">{SOURCE[it.source]}</span> : null}
                <span className="badge" data-status={it.status}>{STATUS[it.status]}</span>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
})
