import type { Snapshot, TimelineItem } from '../types'
import { greeting, uptime } from '../lib/format'
import { StatCard } from '../components/StatCard'
import { Timeline } from '../components/Timeline'
import { JarvisPanel } from '../components/JarvisPanel'
import { ClaudeThreadsPanel } from '../components/CloudPanels'
import { todayAgenda } from '../lib/agenda'
import { useDigestRefreshing } from '../api/digestRefresh'
import { AgendaDetail } from '../components/AgendaDetail'
import { detailHref } from '../useHashView'

// The home view, kept to a glance: the greeting with what needs you, the
// Ask Jarvis box, the four stat cards, and what's left today (calendar,
// Jarvis's reminders and jobs, alerts) next to the Claude threads. Everything else has its own page: the requests chart,
// calendar and activity on Schedule; services and the local model on Services.

/** Claude threads waiting on Dylan, from the cloud digest (0 without one). */
function threadsWaiting(s: Snapshot): number {
  if (s.cloud === null) return 0
  let n = 0
  for (const t of s.cloud.threads) if (t.state === 'blocked') n++
  return n
}

/**
 * How many things need Dylan: services not running right, failed runs
 * today, and Claude threads waiting on him.
 */
export function attentionCount(s: Snapshot): number {
  let n = threadsWaiting(s)
  for (const sv of s.services) if (sv.status === 'degraded' || sv.status === 'down') n++
  for (const t of s.today) if (t.status === 'failed') n++
  return n
}

/** The line under the greeting: either all clear, or a link to what needs him. */
function AttentionLine({ count, toClaude }: { count: number; toClaude: boolean }) {
  if (count === 0) return <>Everything is running.</>
  let text = `${count} things need you.`
  if (count === 1) text = 'One thing needs you.'
  // Threads waiting on him are usually the most actionable, so go there first.
  let href = '#schedule'
  if (toClaude) href = '#claude'
  return <a href={href} className="hero__alert">{text}</a>
}

/** Each Today row opens its detail. Defined once so the memoized Timeline doesn't redraw. */
const todayLink = (item: TimelineItem) => detailHref('overview', 'j', item.id)

/** The overview page. */
export function Overview({ data, now }: { data: Snapshot; now: Date }) {
  const needs = attentionCount(data)
  // The calendar half of Today comes from Jarvis's digest, so say when it's being refreshed.
  let note: string | undefined
  if (useDigestRefreshing()) note = 'Updating from Jarvis…'
  return (
    <>
      <section className="hero">
        <h1 className="hero__title">{greeting(now)}, Dylan</h1>
        <p className="hero__sub">
          {data.host.name} has been up {uptime(data.host.uptimeSec)}.{' '}
          <AttentionLine count={needs} toClaude={threadsWaiting(data) > 0} />
        </p>
      </section>

      <JarvisPanel />

      <div className="grid grid--stats">
        {data.metrics.map((m) => <StatCard key={m.id} metric={m} />)}
      </div>

      <div className="grid grid--split">
        <Timeline items={todayAgenda(data, now)} now={now} limit={5} upcoming presorted empty="Nothing else today." note={note} linkTo={todayLink} moreHref="#schedule" />
        <ClaudeThreadsPanel cloud={data.cloud} now={now} compact />
      </div>
      <AgendaDetail data={data} now={now} />
    </>
  )
}
