import { useState } from 'react'
import { useSWRConfig } from 'swr'
import type { ActionName, Snapshot } from '../types'
import { runAction, SNAPSHOT_KEY } from '../api/client'
import { ConfirmDialog } from './ConfirmDialog'

// The Gemma card: how much GPU memory it holds, and a button to unload it
// before gaming (it holds about 10 of the RTX 3060's 12 GB) or load it back,
// which takes about three minutes.

/** The card, plus its confirm dialog while open. */
export function ModelCard({ model, onDone }: { model: Snapshot['model']; onDone: (msg: string) => void }) {
  const { mutate } = useSWRConfig()
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const action: ActionName = model.loaded ? 'ollama-unload' : 'ollama-load'

  /** Runs the action; closes on success, keeps the dialog open with the error otherwise. */
  async function confirm() {
    setBusy(true)
    setError(null)
    try {
      const result = await runAction(action)
      // Refetch either way: a failed action can still have changed things.
      await mutate(SNAPSHOT_KEY)
      if (result.ok) {
        setOpen(false)
        onDone(result.message)
      } else {
        setError(result.message)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The request failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="glass panel model" aria-labelledby="model-title">
      <header className="panel__head">
        <div>
          <h2 id="model-title" className="panel__title">Gemma</h2>
          <p className="panel__sub">{model.name} · Jarvis’s chat brain in Ollama</p>
        </div>
      </header>
      <div className="model__ring" style={{ '--fill': model.loaded ? Math.min(1, model.vramGb / 12) : 0 } as React.CSSProperties}>
        <span className="model__gb">{model.loaded ? `${model.vramGb} GB` : 'Unloaded'}</span>
        <span className="model__of">{model.loaded ? 'of 12 GB GPU' : 'GPU is free'}</span>
      </div>
      <button type="button" className="btn btn--wide" onClick={() => { setError(null); setOpen(true) }}>
        {model.loaded ? 'Unload Gemma' : 'Load Gemma'}
      </button>
      {open ? (
        <ConfirmDialog
          title={model.loaded ? 'Unload Gemma?' : 'Load Gemma?'}
          body={model.loaded
            ? 'This frees about 10 GB of GPU memory for games. Jarvis and Open WebUI can’t use Gemma until it loads again, which takes about 3 minutes.'
            : 'Loading takes about 3 minutes and uses about 10 GB of GPU memory.'}
          confirmLabel={model.loaded ? 'Unload' : 'Load'}
          busyLabel={model.loaded ? 'Unloading Gemma…' : 'Loading Gemma, about 3 minutes…'}
          busy={busy}
          error={error}
          onConfirm={confirm}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </section>
  )
}
