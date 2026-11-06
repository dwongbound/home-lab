import { memo } from 'react'
import { sparkPath } from '../lib/sparkline'

const W = 120
const H = 40

// A tiny line chart with a soft fill under it. Draws nothing until there
// are at least two points (the live source starts with an empty history).

/** The sparkline. `tone` picks the colour from the card's CSS. */
export const Sparkline = memo(function Sparkline({ values, tone }: { values: number[]; tone: string }) {
  const d = sparkPath(values, W, H)
  if (!d) return <div className="spark spark--empty" aria-hidden="true" />
  return (
    <svg className="spark" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden="true" data-tone={tone}>
      <path d={`${d}L${W - 2} ${H}L2 ${H}Z`} className="spark__fill" />
      <path d={d} className="spark__line" />
    </svg>
  )
})
