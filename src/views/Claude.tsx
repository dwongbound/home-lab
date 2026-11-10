// The Claude page: every project thread by state, plus what's shipping.
import type { Snapshot } from '../types'
import { ClaudeThreadsPanel, ShippingPanel } from '../components/CloudPanels'

/** The Claude page. */
export function Claude({ data, now }: { data: Snapshot; now: Date }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Claude</h1></section>
      <div className="grid grid--split">
        <ClaudeThreadsPanel cloud={data.cloud} now={now} />
        <ShippingPanel cloud={data.cloud} now={now} />
      </div>
    </>
  )
}
