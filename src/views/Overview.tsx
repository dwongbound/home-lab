import type { Snapshot } from '../types'
import { greeting, uptime } from '../lib/format'
import { StatCard } from '../components/StatCard'
import { RequestsChart } from '../components/RequestsChart'
import { Timeline } from '../components/Timeline'
import { ActivityList } from '../components/ActivityList'
import { ServicesPanel } from '../components/ServicesPanel'
import { ModelCard } from '../components/ModelCard'
import { JarvisPanel } from '../components/JarvisPanel'
import { CalendarPanel, ClaudeThreadsPanel } from '../components/CloudPanels'

// The home view: greeting, four stat cards, the Ask Jarvis box, the
// requests chart, today's schedule, recent activity, services and the
// Gemma card.

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

/** The overview page. */
export function Overview({ data, now, onToast }: { data: Snapshot; now: Date; onToast: (m: string) => void }) {
  const needs = attentionCount(data)
  return (
    <>
      <section className="hero">
        <h1 className="hero__title">{greeting(now)}, Dylan</h1>
        <p className="hero__sub">
          {data.host.name} has been up {uptime(data.host.uptimeSec)}.{' '}
          <AttentionLine count={needs} toClaude={threadsWaiting(data) > 0} />
        </p>
      </section>

      <div className="grid grid--stats">
        {data.metrics.map((m) => <StatCard key={m.id} metric={m} />)}
      </div>

      <JarvisPanel />

      <div className="grid grid--main">
        <RequestsChart days={data.requests} />
        <Timeline items={data.today} now={now} limit={4} />
      </div>

      <div className="grid grid--split">
        <ClaudeThreadsPanel cloud={data.cloud} now={now} compact />
        <CalendarPanel cloud={data.cloud} now={now} />
      </div>

      <div className="grid grid--lower">
        <ActivityList items={data.activity} now={now} />
        <ServicesPanel services={data.services} />
        <ModelCard model={data.model} onDone={onToast} />
      </div>
    </>
  )
}
