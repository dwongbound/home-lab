import { memo } from 'react'
import { shownPhase } from '../lib/sky'

// A painted view out of a window: sky, a low sun and a far ridge line.
// Pure CSS and one static SVG, so it costs nothing to keep on screen.
// (It used to have window frame bars too; seen through the frosted
// panels they read as dark shading glitches, so they're gone.)
const Ridge = (
  <svg className="backdrop__ridge" viewBox="0 0 1440 220" preserveAspectRatio="none" aria-hidden="true">
    <path d="M0 150 L120 128 L210 140 L330 96 L420 118 L540 84 L640 112 L760 70 L880 104 L990 90 L1110 120 L1230 98 L1340 126 L1440 110 V220 H0 Z" />
  </svg>
)

/**
 * The backdrop. `override` is the Settings choice; "auto" (or nothing)
 * follows the clock.
 */
export const Backdrop = memo(function Backdrop({ now, override }: { now: Date; override?: string | null }) {
  const phase = shownPhase(now, override)
  // A sky picked in Settings fades in quickly; the clock's changes fade slowly (styles.css).
  const picked = Boolean(override) && override !== 'auto'
  return (
    <div className="backdrop" data-phase={phase} data-picked={picked ? '' : undefined} aria-hidden="true">
      <div className="backdrop__sky" />
      <div className="backdrop__sun" />
      {Ridge}
      <div className="backdrop__grain" />
    </div>
  )
})
