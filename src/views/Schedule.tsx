import type { Snapshot } from '../types'
import { Timeline } from '../components/Timeline'
import { ActivityList } from '../components/ActivityList'
import { CalendarPanel, EmailPanel } from '../components/CloudPanels'

// The Schedule page: today's runs on jarvis and your calendar, then email
// needing you and recent activity.

/** The schedule page. */
export function Schedule({ data, now }: { data: Snapshot; now: Date }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Schedule</h1></section>
      <div className="grid grid--split">
        <Timeline items={data.today} now={now} />
        <CalendarPanel cloud={data.cloud} now={now} />
      </div>
      <div className="grid grid--split">
        <EmailPanel cloud={data.cloud} now={now} />
        <ActivityList items={data.activity} now={now} />
      </div>
    </>
  )
}
