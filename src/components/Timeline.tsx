import { memo } from 'react'
import type { RunStatus, TimelineItem } from '../types'
import { clock } from '../lib/format'

// Today's scheduled runs on jarvis, in time order, each with a coloured
// edge for its state (done, failed, running, later).

const STATUS: Record<RunStatus, string> = { done: 'Done', failed: 'Failed', running: 'Running', scheduled: 'Later' }

/** The timeline panel. `limit` trims it for the overview. */
export const Timeline = memo(function Timeline({ items, now, title = 'Today', limit }: { items: TimelineItem[]; now: Date; title?: string; limit?: number }) {
  const dateLabel = new Intl.DateTimeFormat('en-US', { weekday: 'long', month: 'short', day: 'numeric' }).format(now)
  const sorted = items.toSorted((a, b) => a.at.localeCompare(b.at))
  const shown = limit ? sorted.slice(0, limit) : sorted
  return (
    <section className="glass panel timeline" aria-labelledby="today-title">
      <header className="panel__head">
        <div>
          <h2 id="today-title" className="panel__title">{title}</h2>
          <p className="panel__sub">{dateLabel}</p>
        </div>
      </header>
      {shown.length === 0 ? (
        <p className="empty">Nothing scheduled on jarvis today.</p>
      ) : (
        <ol className="timeline__list">
          {shown.map((it) => (
            <li key={it.id} className="timeline__item" data-status={it.status}>
              <time className="timeline__time" dateTime={it.at}>{clock(it.at)}</time>
              <div className="timeline__card">
                <p className="timeline__title">{it.title}</p>
                <p className="timeline__detail">{it.detail}</p>
                <span className="badge" data-status={it.status}>{STATUS[it.status]}</span>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
})
