import type { GpuUse } from '../types'
import { gpuSlices, gpuSummary, memoryText } from '../lib/gpu'

// The graphics card as a pie: who holds its memory right now (the local
// model, Jarvis's speech and voice models, everything else) and how much is
// free (Dylan, 2026-11-18). A ring drawn with plain SVG strokes, no chart
// library; the list beside it says the same thing in words.

/** The ring's radius in its 100-wide box; each slice is one stroked circle of this size. */
const RADIUS = 40
const ROUND = 2 * Math.PI * RADIUS

/** The panel. Shows a plain line when the card can't be read. */
export function GpuPie({ gpu }: { gpu: GpuUse | null }) {
  if (gpu === null) {
    return (
      <section className="glass panel" aria-labelledby="gpu-title">
        <header className="panel__head"><h2 id="gpu-title" className="panel__title">Graphics card</h2></header>
        <p className="empty">The graphics card isn&rsquo;t reporting right now.</p>
      </section>
    )
  }
  const slices = gpuSlices(gpu)
  return (
    <section className="glass panel gpu" aria-labelledby="gpu-title">
      <header className="panel__head">
        <div>
          <h2 id="gpu-title" className="panel__title">Graphics card</h2>
          <p className="panel__sub">{gpuSummary(gpu)}</p>
        </div>
      </header>
      <div className="gpu__body">
        <div className="gpu__chart">
          {/* The list beside the ring carries the numbers, so the drawing is hidden from screen readers. */}
          <svg className="gpu__ring" viewBox="0 0 100 100" aria-hidden="true">
            {slices.map((slice) => (
              <circle
                key={slice.name}
                cx="50" cy="50" r={RADIUS} fill="none" strokeWidth="14"
                stroke={slice.color}
                strokeDasharray={`${slice.share * ROUND} ${ROUND}`}
                strokeDashoffset={-slice.start * ROUND}
              />
            ))}
          </svg>
          <p className="gpu__centre">
            <span className="gpu__used">{memoryText(gpu.usedMb)}</span>
            <span className="gpu__of">of {memoryText(gpu.totalMb)}</span>
          </p>
        </div>
        <ul className="gpu__legend">
          {slices.map((slice) => (
            <li key={slice.name} className="gpu__row">
              <span className="gpu__dot" style={{ background: slice.color }} />
              <span className="gpu__who">
                <span className="gpu__name">{slice.name}</span>
                <span className="gpu__role">{slice.role}</span>
              </span>
              <span className="gpu__mb">{memoryText(slice.mb)}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
