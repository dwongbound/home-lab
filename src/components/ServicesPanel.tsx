import { memo } from 'react'
import type { Service, ServiceStatus } from '../types'
import { Icon } from './Icon'

// The services jarvis runs, each with a status dot and a link to open it.

/** Plain words for each status, shown before the service's own detail. */
const LABEL: Record<ServiceStatus, string> = { up: 'Running', idle: 'Idle', degraded: 'Needs attention', down: 'Not responding' }

/** The services panel. `detailed` adds response times (Services page). */
export const ServicesPanel = memo(function ServicesPanel({ services, detailed = false }: { services: Service[]; detailed?: boolean }) {
  return (
    <section className={`glass panel services${detailed ? ' services--detailed' : ''}`} aria-labelledby="services-title">
      <header className="panel__head">
        <div>
          <h2 id="services-title" className="panel__title">Services</h2>
          <p className="panel__sub">{services.filter((s) => s.status === 'up').length} of {services.length} running</p>
        </div>
      </header>
      <ul className="services__list">
        {services.map((s) => (
          <li key={s.id} className="services__item">
            <span className="dot" data-status={s.status} aria-hidden="true" />
            <div className="services__text">
              <p className="services__name">{s.name}</p>
              <p className="services__detail">{LABEL[s.status]}. {s.detail}</p>
            </div>
            {detailed && s.latencyMs != null ? <span className="services__ms">{s.latencyMs} ms</span> : null}
            {s.url ? (
              <a className="icon-btn" href={s.url} target="_blank" rel="noreferrer" aria-label={`Open ${s.name}`}>
                <Icon name="external" size={16} />
              </a>
            ) : <span className="services__nolink" aria-hidden="true" />}
          </li>
        ))}
      </ul>
    </section>
  )
})
