import type { JarvisJob, JarvisJobs } from '../types'
import { ago } from '../lib/format'

// "What Jarvis is doing": the three jobs that think (Lookout, Messenger,
// Nightly) with when each last ran, what it found and when it runs next,
// then what Lookout is keeping an eye on and what it chose not to send,
// and finally the quiet housekeeping in one short list.

/** Status words shown next to a job's name. */
const STATUS: Record<JarvisJob['status'], string> = {
  ok: 'OK',
  running: 'Running',
  error: 'Error',
  paused: 'Paused',
}

/** A model id in plain words: "Opus", "Ornith on the PC", or the id itself. */
export function modelLabel(model: string | null): string | null {
  if (model === null) return null
  const id = model.toLowerCase()
  if (id.includes('opus')) return 'Opus'
  if (id.includes('sonnet')) return 'Sonnet'
  if (id.includes('haiku')) return 'Haiku'
  if (id.startsWith('ornith')) return 'Ornith on the PC'
  return model
}

/** "in 19 min", "in 3 h", or "now" for a time that has come. */
export function inTime(iso: string, now: Date): string {
  const min = Math.round((Date.parse(iso) - now.getTime()) / 60_000)
  if (min < 1) return 'now'
  if (min < 60) return `in ${min} min`
  return `in ${Math.round(min / 60)} h`
}

/** "Ran 11 min ago · next in 19 min", leaving out what's unknown. */
export function runLine(job: JarvisJob, now: Date): string {
  const parts: string[] = []
  if (job.lastRun) parts.push(`Ran ${ago(job.lastRun, now)}`)
  else parts.push('Hasn’t run yet')
  if (job.nextRun) parts.push(`next ${inTime(job.nextRun, now)}`)
  return parts.join(' · ')
}

/** A tool name like drive_time as "drive time". */
function toolLabel(name: string): string {
  return name.replaceAll('_', ' ')
}

/** One of the three main jobs. */
function MainJob({ job, now }: { job: JarvisJob; now: Date }) {
  const about = [modelLabel(job.model), job.schedule].filter(Boolean).join(' · ')
  return (
    <li className="loaded__item jobs__item">
      <p className="money__line">
        <span className="loaded__name">{job.name}</span>
        <span className="jobs__status" data-status={job.status}>{STATUS[job.status]}</span>
      </p>
      {about && <p className="loaded__role">{about}</p>}
      {job.lastResult && <p className="jobs__result">{job.lastResult}</p>}
      <p className="cloud__meta loaded__meta">{runLine(job, now)}</p>
    </li>
  )
}

/** The panel. Shows a plain note when Jarvis doesn't report its jobs yet. */
export function JobsPanel({ jobs, now }: { jobs: JarvisJobs | null; now: Date }) {
  if (jobs === null) {
    return (
      <section className="glass panel" aria-labelledby="jobs-title">
        <h2 id="jobs-title" className="panel__title">What Jarvis is doing</h2>
        <p className="empty">Jarvis isn’t reporting its background jobs right now.</p>
      </section>
    )
  }
  const main = jobs.jobs.filter((j) => j.group === 'main')
  const housekeeping = jobs.jobs.filter((j) => j.group === 'housekeeping')
  const messenger = jobs.messenger
  let sub = `${main.length} jobs`
  if (messenger) {
    sub = `${messenger.sentToday} of ${messenger.cap} pings sent today`
    if (messenger.quiet) sub += ` · Quiet: ${messenger.quiet}`
  }
  const lookout = jobs.lookout
  return (
    <section className="glass panel" aria-labelledby="jobs-title">
      <header className="panel__head">
        <div>
          <h2 id="jobs-title" className="panel__title">What Jarvis is doing</h2>
          <p className="panel__sub">{sub}</p>
        </div>
      </header>
      <ul className="cloud__list loaded__list">
        {main.map((job) => <MainJob key={job.id} job={job} now={now} />)}
      </ul>
      {lookout && lookout.checks.length > 0 && (
        <p className="cloud__meta loaded__meta jobs__checks">Last looked at: {lookout.checks.map(toolLabel).join(', ')}</p>
      )}
      {lookout && lookout.watching.length > 0 && (
        <>
          <h3 className="jobs__heading">Keeping an eye on</h3>
          <ul className="jobs__plain">
            {lookout.watching.map((w) => <li key={w}>{w}</li>)}
          </ul>
        </>
      )}
      {lookout && lookout.heldBack.length > 0 && (
        <>
          <h3 className="jobs__heading">Decided not to bother you with</h3>
          <ul className="jobs__plain">
            {lookout.heldBack.map((h) => (
              <li key={h.text}>{h.text}{h.reason && <span className="jobs__why"> {h.reason}</span>}</li>
            ))}
          </ul>
        </>
      )}
      {housekeeping.length > 0 && (
        <>
          <h3 className="jobs__heading">Quiet housekeeping</h3>
          <ul className="jobs__plain">
            {housekeeping.map((job) => (
              <li key={job.id}>
                {job.name}
                <span className="jobs__why"> {[job.schedule, runLine(job, now)].filter(Boolean).join(' · ')}</span>
                {job.status === 'error' && <span className="jobs__status" data-status="error"> Error</span>}
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  )
}
