import type { Snapshot } from '../types'
import { ServicesPanel } from '../components/ServicesPanel'
import { ModelCard } from '../components/ModelCard'
import { LoadedModels } from '../components/LoadedModels'
import { TerminalPanel } from './Shell'

// The Services page: every service with response times, the Gemma card,
// what's in GPU memory and why, and a terminal on jarvis (the same tmux
// session as the Shell tab) for restarting things by hand.

/** The services page. */
export function Services({ data, now, onToast }: { data: Snapshot; now: Date; onToast: (m: string) => void }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Services</h1></section>
      <div className="grid grid--split">
        <div className="stack">
          <ServicesPanel services={data.services} detailed />
          <LoadedModels models={data.models} now={now} />
        </div>
        <ModelCard model={data.model} onDone={onToast} />
      </div>
      <TerminalPanel compact />
    </>
  )
}
