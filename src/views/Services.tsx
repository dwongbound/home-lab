import type { Snapshot } from '../types'
import { ServicesPanel } from '../components/ServicesPanel'
import { ModelCard } from '../components/ModelCard'

// The Services page: every service with response times, and the Gemma card.

/** The services page. */
export function Services({ data, onToast }: { data: Snapshot; onToast: (m: string) => void }) {
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Services</h1></section>
      <div className="grid grid--split">
        <ServicesPanel services={data.services} detailed />
        <ModelCard model={data.model} onDone={onToast} />
      </div>
      <section className="glass panel note">
        <h2 className="panel__title">Restarting Jarvis</h2>
        <p>Restarting the <code>jarvis</code> service needs your password, so this page can’t do it. On the PC, run <code>sudo systemctl restart jarvis</code> in Ubuntu.</p>
      </section>
    </>
  )
}
