import { JarvisOrb } from './JarvisOrb'
import type { LoaderPhase } from '../useLoaderExit'

// The full-page loader while the first snapshot is on its way: Jarvis's own
// orb (the one beside Ask Jarvis and in the app), large and turning as it
// does when he thinks, over "Jarvis is thinking..." with dots that bounce.
// It sits on top of the page, in the middle of the screen, so when the data
// arrives it can leave smoothly (`phase: leaving`): the words fade, the orb
// lifts and shrinks away, and the panels fade in underneath.
// Nothing here is glass, so it can move freely. With reduced motion it's a
// still orb, and the words still say what's happening.

/** The orb's core size here; its constellation reaches about as far again on each side. */
const LOADER_ORB = 'clamp(56px, 13vmin, 104px)'

/** The full-page "Jarvis is thinking..." loader, announced to screen readers until it starts to leave. */
export function ThinkingLoader({ phase }: { phase: LoaderPhase }) {
  if (phase === 'off') return null
  const leaving = phase === 'leaving'
  return (
    <div className="thinking" role={leaving ? undefined : 'status'} aria-hidden={leaving || undefined} data-leaving={leaving || undefined}>
      <div className="thinking__orb" aria-hidden="true">
        <JarvisOrb state="thinking" size={LOADER_ORB} />
      </div>
      <p className="thinking__label">
        Jarvis is thinking
        <span className="thinking__dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>
    </div>
  )
}
