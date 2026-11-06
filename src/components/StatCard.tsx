import { memo } from 'react'
import type { Metric } from '../types'
import { share } from '../lib/format'
import { Icon, type IconName } from './Icon'
import { Sparkline } from './Sparkline'

const ICON: Record<Metric['id'], IconName> = { ram: 'memory', gpu: 'gpu', cpu: 'chip', disk: 'disk' }

// One small card per metric: memory, GPU memory, processor, free disk.

/**
 * Colour band for a metric: calm under 70% load, warm to 90%, hot above.
 * Free disk is the odd one out, since more free space is good, so its
 * load is the used share rather than the free share.
 */
function tone(m: Metric): 'calm' | 'warm' | 'hot' {
  const s = share(m.value, m.total)
  if (s == null) return 'calm'
  const load = m.id === 'disk' ? 1 - s : s
  if (load > 0.9) return 'hot'
  if (load > 0.7) return 'warm'
  return 'calm'
}

/** "of 16 GB" under the number, or the sparkline's time span for percentages. */
function footnote(m: Metric): string {
  if (m.total == null || m.unit === '%') return 'Last 12 min'
  return `of ${m.total} ${m.unit}`
}

/** Percent sits tight against the number; units get a space ("11.4 GB"). */
function unitText(unit: string): string {
  if (unit === '%') return '%'
  return ` ${unit}`
}

/** The card. memo'd because the parent re-renders every 15 s refresh. */
export const StatCard = memo(function StatCard({ metric }: { metric: Metric }) {
  const t = tone(metric)
  const s = share(metric.value, metric.total)
  return (
    <article className="glass stat" data-tone={t}>
      <header className="stat__head">
        <span className="stat__icon"><Icon name={ICON[metric.id]} /></span>
        <h3 className="stat__label">{metric.label}</h3>
      </header>
      <p className="stat__value">
        {metric.value == null ? (
          <span className="stat__na">Not reporting</span>
        ) : (
          <>
            {metric.value}<span className="stat__unit">{unitText(metric.unit)}</span>
          </>
        )}
      </p>
      <div className="stat__foot">
        <span className="stat__of">{footnote(metric)}</span>
        <Sparkline values={metric.history} tone={t} />
      </div>
      {/* A thin bar along the bottom edge showing how full it is. */}
      {s != null ? <div className="stat__meter" style={{ '--fill': s } as React.CSSProperties} aria-hidden="true" /> : null}
    </article>
  )
})
