import type { Snapshot } from '../types'
import type { SkyPhase } from '../lib/sky'
import type { WakeState } from '../useWakeLock'
import { MemoryPanel } from '../components/MemoryPanel'

// The Settings page: the sky choice and keep-awake (per browser), where the
// data comes from, and Memory (what Jarvis remembers) at the bottom.

export type SkyChoice = SkyPhase | 'auto'
const CHOICES: { id: SkyChoice; label: string }[] = [
  { id: 'auto', label: 'Follow the clock' },
  { id: 'dawn', label: 'Dawn' },
  { id: 'day', label: 'Day' },
  { id: 'dusk', label: 'Dusk' },
  { id: 'night', label: 'Night' },
]

/** The line under the keep-awake switch, saying what's actually happening. */
function awakeNote(awake: boolean, state: WakeState): string {
  if (!awake) return 'Off. The screen sleeps as usual.'
  if (state === 'unsupported') return 'This browser can’t keep the screen on. On an iPad, set Settings › Display & Brightness › Auto-Lock to Never instead.'
  if (state === 'on') return 'On. The screen stays on while this page is showing.'
  return 'On. Waiting for the page to be showing.'
}

interface SettingsProps {
  data: Snapshot
  now: Date
  sky: SkyChoice
  onSky: (s: SkyChoice) => void
  awake: boolean
  wake: WakeState
  onAwake: (on: boolean) => void
}

/** The settings page. */
export function Settings({ data, now, sky, onSky, awake, wake, onAwake }: SettingsProps) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Settings</h1></section>
      <div className="grid grid--split">
        <section className="glass panel">
          <h2 className="panel__title">Sky</h2>
          <p className="panel__sub">The window behind the page. Saved in this browser only.</p>
          <div className="segmented" role="radiogroup" aria-label="Sky">
            {CHOICES.map((c) => (
              <button key={c.id} type="button" role="radio" aria-checked={sky === c.id} className="segmented__opt" onClick={() => onSky(c.id)}>
                {c.label}
              </button>
            ))}
          </div>
        </section>
        <section className="glass panel">
          <h2 className="panel__title">Keep this screen on</h2>
          <p className="panel__sub">For an iPad left up as a display. Saved in this browser only.</p>
          <button type="button" role="switch" aria-checked={awake} className="switch" onClick={() => onAwake(!awake)}>
            <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
            <span>Keep the screen on</span>
          </button>
          <p className="cloud__foot" role="status">{awakeNote(awake, wake)}</p>
        </section>
        <section className="glass panel note">
          <h2 className="panel__title">Data</h2>
          {data.source === 'mock' ? (
            <p>This page is showing sample numbers. To read the real PC, start the server with <code>DATA_SOURCE=live</code> and put the Home Assistant token in <code>.env</code>. The token stays on the server and never reaches this page.</p>
          ) : (
            <p>Reading live from {data.host.name} every 15 seconds.</p>
          )}
        </section>
        <MemoryPanel now={now} />
      </div>
    </>
  )
}
