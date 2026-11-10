import type { Snapshot, TimelineItem } from '../types'
import { RequestsChart } from '../components/RequestsChart'
import { Timeline } from '../components/Timeline'
import { ActivityList } from '../components/ActivityList'
import { CalendarPanel, EmailPanel } from '../components/CloudPanels'
import { AgendaDetail } from '../components/AgendaDetail'
import { detailHref } from '../useHashView'

// The Schedule page: today's runs on jarvis and your calendar, then email
// needing you and recent activity, then Jarvis's requests this week.

/** Each Jarvis row opens its detail. Defined once so the memoized Timeline doesn't redraw. */
const jarvisLink = (item: TimelineItem) => detailHref('schedule', 'j', item.id)

/** The schedule page. */
export function Schedule({ data, now }: { data: Snapshot; now: Date }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Schedule</h1></section>
      <div className="grid grid--split">
        <Timeline items={data.today} now={now} title="Jarvis today" linkTo={jarvisLink} />
        <CalendarPanel cloud={data.cloud} now={now} view="schedule" />
      </div>
      <div className="grid grid--split">
        <EmailPanel cloud={data.cloud} now={now} view="schedule" />
        <ActivityList items={data.activity} now={now} />
      </div>
      <RequestsChart days={data.requests} />
      <AgendaDetail data={data} now={now} />
    </>
  )
}
