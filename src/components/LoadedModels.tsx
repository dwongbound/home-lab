import type { LoadedModel } from '../types'

// What's in the GPU right now: every model Ollama has loaded, with its job
// on jarvis, how much GPU memory it holds and when it unloads. Gemma is
// Jarvis's chat brain; Jarvis's watch model (Qwen) scores new items in the
// background and steps aside whenever Gemma loads.

/** Each role in plain words. */
const ROLE: Record<LoadedModel['role'], string> = {
  chat: 'Chat brain for Jarvis and Open WebUI.',
  watch: 'Jarvis’s background watch: scores new items against your interests and, once an hour, looks for ones that connect. Unloads itself when Gemma loads.',
  other: 'Loaded by something else (Open WebUI or a script).',
}

/** "Unloads in 52 min" style text, or that it stays. */
function untilText(until: string | null, now: Date): string {
  if (until === null) return 'Stays loaded'
  const min = Math.round((Date.parse(until) - now.getTime()) / 60_000)
  if (min < 1) return 'Unloading now'
  if (min < 60) return `Unloads in ${min} min if unused`
  return `Unloads in ${Math.round(min / 60)} h if unused`
}

/** Size, quantization and context, from what Ollama says. */
function specs(m: LoadedModel): string {
  const parts: string[] = []
  if (m.parameters) parts.push(`${m.parameters} parameters`)
  if (m.quantization) parts.push(m.quantization)
  if (m.contextLength) parts.push(`${m.contextLength.toLocaleString('en-US')} token context`)
  return parts.join(' · ')
}

/** The panel. */
export function LoadedModels({ models, now }: { models: LoadedModel[]; now: Date }) {
  let used = 0
  for (const m of models) used += m.vramGb
  return (
    <section className="glass panel" aria-labelledby="loaded-title">
      <header className="panel__head">
        <div>
          <h2 id="loaded-title" className="panel__title">In GPU memory</h2>
          <p className="panel__sub">{models.length === 0 ? 'Nothing loaded' : `${Math.round(used * 10) / 10} of 12 GB used by models`}</p>
        </div>
      </header>
      {models.length === 0 ? <p className="empty">No model is loaded. Gemma loads when Jarvis needs it, or with Load Gemma.</p> : (
        <ul className="cloud__list loaded__list">
          {models.map((m) => (
            <li key={m.name} className="loaded__item">
              <p className="money__line"><span className="loaded__name">{m.name}</span><span className="loaded__gb">{m.vramGb} GB</span></p>
              <p className="loaded__role">{ROLE[m.role]}</p>
              <p className="cloud__meta loaded__meta">{[untilText(m.until, now), specs(m)].filter(Boolean).join(' · ')}</p>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
