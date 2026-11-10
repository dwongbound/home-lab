// Panels fed by the cloud digest (docs/digest.md): Claude threads, today's
// calendar, email needing Dylan, and what's shipping (deploys and PRs).
// Each says how old the digest is, since it's written every 15 minutes.
import { memo } from 'react'
import type { CalendarEvent, ClaudeThread, CloudDigest, Deploy, EmailItem, PullRequest, ThreadState } from '../types'
import { ago, clock } from '../lib/format'
import { Icon } from './Icon'

/** Section names for each thread state, in the order they're shown. */
const STATE_GROUPS: { state: ThreadState; label: string }[] = [
  { state: 'blocked', label: 'Waiting on you' },
  { state: 'working', label: 'Working' },
  { state: 'review_ready', label: 'Ready for review' },
  { state: 'failed', label: 'Failed' },
]

/** The "Updated 12 min ago" line every cloud panel carries. */
function UpdatedLine({ cloud, now }: { cloud: CloudDigest; now: Date }) {
  return <p className="panel__sub">Updated {ago(cloud.updatedAt, now)}</p>
}

/** What a cloud panel shows before the digest is set up. */
function NotSetUp({ what }: { what: string }) {
  return <p className="empty">{what} will show here once the Claude digest is set up. The README's “Cloud digest” section has the steps.</p>
}

/** One thread row: state dot, title linking to the thread, last activity. */
function ThreadRow({ thread, now }: { thread: ClaudeThread; now: Date }) {
  return (
    <li className="cloud__row">
      <span className="dot" data-thread={thread.state} aria-hidden="true" />
      <a className="cloud__title" href={thread.url} target="_blank" rel="noreferrer">{thread.title}</a>
      <time className="cloud__meta" dateTime={thread.lastActivityAt}>{ago(thread.lastActivityAt, now)}</time>
    </li>
  )
}

/**
 * Claude project threads grouped by state, waiting-on-you first.
 * `compact` (the overview) leaves out finished threads entirely.
 */
export const ClaudeThreadsPanel = memo(function ClaudeThreadsPanel({ cloud, now, compact = false }: { cloud: CloudDigest | null; now: Date; compact?: boolean }) {
  if (cloud === null) {
    return (
      <section className="glass panel" aria-labelledby="claude-title">
        <header className="panel__head"><h2 id="claude-title" className="panel__title">Claude threads</h2></header>
        <NotSetUp what="Your Claude project threads" />
      </section>
    )
  }

  let doneCount = 0
  for (const t of cloud.threads) if (t.state === 'done') doneCount++

  return (
    <section className="glass panel" aria-labelledby="claude-title">
      <header className="panel__head">
        <div>
          <h2 id="claude-title" className="panel__title">Claude threads</h2>
          <UpdatedLine cloud={cloud} now={now} />
        </div>
        {compact ? <a className="icon-btn" href="#claude" aria-label="All Claude threads"><Icon name="claude" size={16} /></a> : null}
      </header>
      {STATE_GROUPS.map((group) => {
        const threads = cloud.threads.filter((t) => t.state === group.state)
        if (threads.length === 0) return null
        return (
          <div key={group.state} className="cloud__group">
            <h3 className="cloud__label">{group.label} <span className="cloud__count">{threads.length}</span></h3>
            <ul className="cloud__list">
              {threads.map((t) => <ThreadRow key={t.id} thread={t} now={now} />)}
            </ul>
          </div>
        )
      })}
      {compact ? (
        <p className="cloud__foot">{doneCount} finished</p>
      ) : (
        <FinishedThreads threads={cloud.threads} now={now} />
      )}
    </section>
  )
})

/** The finished threads, newest first, on the full Claude page. */
function FinishedThreads({ threads, now }: { threads: ClaudeThread[]; now: Date }) {
  const done = threads
    .filter((t) => t.state === 'done' || t.state === 'stopped')
    .toSorted((a, b) => b.lastActivityAt.localeCompare(a.lastActivityAt))
  if (done.length === 0) return null
  return (
    <div className="cloud__group">
      <h3 className="cloud__label">Finished <span className="cloud__count">{done.length}</span></h3>
      <ul className="cloud__list">
        {done.map((t) => <ThreadRow key={t.id} thread={t} now={now} />)}
      </ul>
    </div>
  )
}

/** The time column for a calendar event: "All day" or its start time. */
function eventTime(event: CalendarEvent): string {
  if (event.allDay) return 'All day'
  return clock(event.start)
}

/** Today's calendar events across all of Dylan's calendars, in time order. */
export const CalendarPanel = memo(function CalendarPanel({ cloud, now }: { cloud: CloudDigest | null; now: Date }) {
  return (
    <section className="glass panel" aria-labelledby="calendar-title">
      <header className="panel__head">
        <div>
          <h2 id="calendar-title" className="panel__title">Calendar</h2>
          {cloud ? <UpdatedLine cloud={cloud} now={now} /> : null}
        </div>
      </header>
      {cloud === null ? <NotSetUp what="Today’s calendar" /> : <CalendarList events={cloud.calendar} />}
    </section>
  )
})

/** The calendar rows, or an empty state when the day is free. */
function CalendarList({ events }: { events: CalendarEvent[] }) {
  if (events.length === 0) return <p className="empty">Nothing on your calendars today.</p>
  const sorted = events.toSorted((a, b) => a.start.localeCompare(b.start))
  return (
    <ul className="cloud__list">
      {sorted.map((e) => (
        <li key={e.id} className="cloud__row cloud__row--event">
          <span className="cloud__time">{eventTime(e)}</span>
          <span className="cloud__title">{e.title}</span>
          <span className="cloud__meta">{e.calendar}</span>
        </li>
      ))}
    </ul>
  )
}

/** Up to three emails that need Dylan, with why. */
export const EmailPanel = memo(function EmailPanel({ cloud, now }: { cloud: CloudDigest | null; now: Date }) {
  return (
    <section className="glass panel" aria-labelledby="email-title">
      <header className="panel__head">
        <div>
          <h2 id="email-title" className="panel__title">Email needing you</h2>
          {cloud ? <UpdatedLine cloud={cloud} now={now} /> : null}
        </div>
      </header>
      {cloud === null ? <NotSetUp what="Email that needs you" /> : <EmailList items={cloud.email} />}
    </section>
  )
})

/** The email rows, or an empty state when nothing needs him. */
function EmailList({ items }: { items: EmailItem[] }) {
  if (items.length === 0) return <p className="empty">Nothing in your inbox needs you.</p>
  return (
    <ul className="cloud__list">
      {items.map((m) => (
        <li key={m.id} className="cloud__row cloud__row--stack">
          <span className="cloud__title">{m.subject}</span>
          <span className="cloud__meta">{m.from}. {m.why}</span>
        </li>
      ))}
    </ul>
  )
}

/** Plain words for a deploy's state. */
const DEPLOY_LABEL: Record<Deploy['state'], string> = { ready: 'Live', building: 'Building', error: 'Failed' }
/** Plain words for a PR's checks. */
const CI_LABEL: Record<PullRequest['ci'], string> = { passing: 'Checks passing', failing: 'Checks failing', running: 'Checks running', none: 'No checks' }

/** Latest deploys of Dylan's sites and his open pull requests. */
export const ShippingPanel = memo(function ShippingPanel({ cloud, now }: { cloud: CloudDigest | null; now: Date }) {
  return (
    <section className="glass panel" aria-labelledby="shipping-title">
      <header className="panel__head">
        <div>
          <h2 id="shipping-title" className="panel__title">Shipping</h2>
          {cloud ? <UpdatedLine cloud={cloud} now={now} /> : null}
        </div>
      </header>
      {cloud === null ? <NotSetUp what="Deploys and pull requests" /> : (
        <>
          <ul className="cloud__list">
            {cloud.deploys.map((d) => (
              <li key={d.project} className="cloud__row">
                <span className="dot" data-deploy={d.state} aria-hidden="true" />
                <a className="cloud__title" href={d.url} target="_blank" rel="noreferrer">{d.project}</a>
                <span className="cloud__meta">{DEPLOY_LABEL[d.state]}, {ago(d.at, now)}</span>
              </li>
            ))}
          </ul>
          <h3 className="cloud__label">Open pull requests <span className="cloud__count">{cloud.pullRequests.length}</span></h3>
          <ul className="cloud__list">
            {cloud.pullRequests.map((pr) => (
              <li key={`${pr.repo}#${pr.number}`} className="cloud__row cloud__row--stack">
                <a className="cloud__title" href={pr.url} target="_blank" rel="noreferrer">{pr.title}</a>
                <span className="cloud__meta" data-ci={pr.ci}>{pr.repo} #{pr.number}. {CI_LABEL[pr.ci]}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
})
