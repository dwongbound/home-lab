import { useState } from 'react'
import type { ActiveAlert } from '../lib/agenda'

// A banner across the top of every page while something needs Dylan right
// now (a service down or not running right). It isn't part of the day's
// list, so it never pushes his calendar around. Tapping it opens Services;
// Close hides it until the set of alerts changes.

/** The alerts as one key, so a new or different alert brings the banner back. */
function keyOf(alerts: ActiveAlert[]): string {
  return alerts.map((a) => `${a.id}:${a.text}`).join('|')
}

/** The banner, or nothing when all is well or it was closed for these alerts. */
export function AlertBanner({ alerts }: { alerts: ActiveAlert[] }) {
  const [closedFor, setClosedFor] = useState<string | null>(null)
  const key = keyOf(alerts)
  if (alerts.length === 0 || closedFor === key) return null
  let more = ''
  if (alerts.length > 1) more = ` +${alerts.length - 1} more`
  return (
    <div className="banner" role="alert">
      <span className="attention__mark" aria-hidden="true">!</span>
      <a className="banner__text" href="#services">
        {alerts[0].text}
        {more ? <span className="banner__more">{more}</span> : null}
      </a>
      <button type="button" className="btn btn--quiet banner__close" aria-label="Close alert" onClick={() => setClosedFor(key)}>Close</button>
    </div>
  )
}
