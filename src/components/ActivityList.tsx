import { memo } from 'react'
import type { ActivityItem } from '../types'
import { ago } from '../lib/format'

// What happened recently across Jarvis, Home Assistant, Ollama and the PC.

/** The initials in each row's circle. */
const KIND: Record<ActivityItem['kind'], string> = { jarvis: 'J', ha: 'HA', ollama: 'G', system: 'PC' }

/** The activity panel. Always newest first, whatever order the server sends. */
export const ActivityList = memo(function ActivityList({ items, now }: { items: ActivityItem[]; now: Date }) {
  const sorted = items.toSorted((a, b) => b.at.localeCompare(a.at))
  return (
    <section className="glass panel" aria-labelledby="activity-title">
      <header className="panel__head">
        <h2 id="activity-title" className="panel__title">Recent activity</h2>
      </header>
      {sorted.length === 0 ? (
        <p className="empty">No activity reported yet.</p>
      ) : (
        <ul className="activity">
          {sorted.map((a) => (
            <li key={a.id} className="activity__item">
              <span className="activity__mark" data-kind={a.kind} aria-hidden="true">{KIND[a.kind]}</span>
              <p className="activity__text">{a.text}</p>
              <time className="activity__ago" dateTime={a.at}>{ago(a.at, now)}</time>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
})
