import type { Snapshot } from '../types'
import { greeting, uptime } from '../lib/format'
import { StatCard } from '../components/StatCard'
import { RequestsChart } from '../components/RequestsChart'
import { Timeline } from '../components/Timeline'
import { ActivityList } from '../components/ActivityList'
import { ServicesPanel } from '../components/ServicesPanel'
import { ModelCard } from '../components/ModelCard'

// The home view: greeting, four stat cards, the requests chart, today's
// schedule, recent activity, services and the Gemma card.

/** How many things need Dylan: services not running right plus failed runs today. */
export function attentionCount(s: Snapshot): number {
  let n = 0
  for (const sv of s.services) if (sv.status === 'degraded' || sv.status === 'down') n++
  for (const t of s.today) if (t.status === 'failed') n++
  return n
}

/** The line under the greeting: either all clear, or a link to what needs him. */
function AttentionLine({ count }: { count: number }) {
  if (count === 0) return <>Everything is running.</>
  let text = `${count} things need you.`
  if (count === 1) text = 'One thing needs you.'
  return <a href="#schedule" className="hero__alert">{text}</a>
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
          <AttentionLine count={needs} />
        </p>
      </section>

      <div className="grid grid--stats">
        {data.metrics.map((m) => <StatCard key={m.id} metric={m} />)}
      </div>

      <div className="grid grid--main">
        <RequestsChart days={data.requests} />
        <Timeline items={data.today} now={now} limit={4} />
      </div>

      <div className="grid grid--lower">
        <ActivityList items={data.activity} now={now} />
        <ServicesPanel services={data.services} />
        <ModelCard model={data.model} onDone={onToast} />
      </div>
    </>
  )
}
