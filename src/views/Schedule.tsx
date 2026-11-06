import type { Snapshot } from '../types'
import { Timeline } from '../components/Timeline'
import { ActivityList } from '../components/ActivityList'

// The Schedule page: the whole of today's timeline next to recent activity.

/** The schedule page. */
export function Schedule({ data, now }: { data: Snapshot; now: Date }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Schedule</h1></section>
      <div className="grid grid--split">
        <Timeline items={data.today} now={now} />
        <ActivityList items={data.activity} now={now} />
      </div>
    </>
  )
}
