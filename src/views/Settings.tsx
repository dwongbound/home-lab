import type { Snapshot } from '../types'
import type { SkyPhase } from '../lib/sky'

// The Settings page: the sky choice (per browser) and where the data comes from.

export type SkyChoice = SkyPhase | 'auto'
const CHOICES: { id: SkyChoice; label: string }[] = [
  { id: 'auto', label: 'Follow the clock' },
  { id: 'dawn', label: 'Dawn' },
  { id: 'day', label: 'Day' },
  { id: 'dusk', label: 'Dusk' },
  { id: 'night', label: 'Night' },
]

/** The settings page. */
export function Settings({ data, sky, onSky }: { data: Snapshot; sky: SkyChoice; onSky: (s: SkyChoice) => void }) {
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
        <section className="glass panel note">
          <h2 className="panel__title">Data</h2>
          {data.source === 'mock' ? (
            <p>This page is showing sample numbers. To read the real PC, start the server with <code>DATA_SOURCE=live</code> and put the Home Assistant token in <code>.env</code>. The token stays on the server and never reaches this page.</p>
          ) : (
            <p>Reading live from {data.host.name} every 15 seconds.</p>
          )}
        </section>
      </div>
    </>
  )
}
