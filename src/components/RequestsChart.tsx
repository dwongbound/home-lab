import { memo } from 'react'
import type { DayCount } from '../types'

// Jarvis requests per day this week, as frosted bars. Today's bar is the
// one lit in blue, like the highlighted bar in the reference design.
// Bars are plain divs sized with a CSS variable: no chart library needed.

/** The chart panel. Shows an empty state until Jarvis reports counts. */
export const RequestsChart = memo(function RequestsChart({ days }: { days: DayCount[] }) {
  let max = 0
  let total = 0
  for (const d of days) { if (d.count > max) max = d.count; total += d.count }
  // Round the scale up to the next 10 so the gridlines land on round numbers.
  const top = Math.max(10, Math.ceil(max / 10) * 10)
  const ticks = [top, top / 2, 0]

  return (
    <section className="glass panel chart" aria-labelledby="chart-title">
      <header className="panel__head">
        <div>
          <h2 id="chart-title" className="panel__title">Jarvis requests</h2>
          <p className="panel__sub">Telegram, Siri and scheduled runs this week</p>
        </div>
        <p className="chart__total"><strong>{total}</strong> so far</p>
      </header>
      {days.length === 0 ? (
        <p className="empty">Jarvis doesn’t report request counts yet. They’ll show here once it does.</p>
      ) : (
        <div className="chart__plot">
          <ol className="chart__ticks" aria-hidden="true">
            {ticks.map((t) => <li key={t}>{t}</li>)}
          </ol>
          <ol className="chart__bars">
            {days.map((d) => (
              <li key={d.day} className="chart__col" data-today={d.today || undefined}>
                <span className="chart__bar" style={{ '--h': d.count / top } as React.CSSProperties} aria-label={`${d.day}: ${d.count} requests`} role="img">
                  <span className="chart__count">{d.count}</span>
                </span>
                <span className="chart__day">{d.today ? 'Today' : d.day}</span>
              </li>
            ))}
          </ol>
        </div>
      )}
    </section>
  )
})
