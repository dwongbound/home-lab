import type { Snapshot } from '../types'
import { ServicesPanel } from '../components/ServicesPanel'
import { ModelCard } from '../components/ModelCard'
import { LoadedModels } from '../components/LoadedModels'
import { TerminalPanel } from '../components/TerminalPanel'
import { JobsPanel } from '../components/JobsPanel'
import { useInKiosk } from '../useKiosk'

// The Services page: every service with response times, the local model card,
// what's in GPU memory and why, what Jarvis is doing in the background,
// and a terminal on jarvis (the same tmux
// session as the Shell tab) for restarting things by hand. Kiosk mode
// leaves the terminal out: a shell on jarvis has no place on a wall display.

/** The services page. */
export function Services({ data, now, onToast }: { data: Snapshot; now: Date; onToast: (m: string) => void }) {
  const kiosk = useInKiosk()
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Services</h1></section>
      <div className="grid grid--split">
        <div className="stack">
          <ServicesPanel services={data.services} detailed />
          <LoadedModels models={data.models} now={now} />
        </div>
        <div className="stack">
          <JobsPanel jobs={data.jobs} now={now} />
          <ModelCard model={data.model} onDone={onToast} />
        </div>
      </div>
      {kiosk ? null : <TerminalPanel />}
    </>
  )
}
