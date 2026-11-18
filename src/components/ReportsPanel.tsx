import { useState } from 'react'
import { useSWRConfig } from 'swr'
import { SNAPSHOT_KEY, changeReport } from '../api/client'
import { ago } from '../lib/format'
import { endText, reportHref, rulesText, sizeText } from '../lib/reports'
import type { JarvisReport, JarvisReports } from '../types'
import { ConfirmDialog } from './ConfirmDialog'
import { Spinner } from './Spinner'

// Reports (Dylan, 2026-11-18): the pages Jarvis writes when a long task
// ends in more than a chat reply can hold. Each row opens the report in its
// own tab and says how big it is and when Jarvis deletes it. Keep holds a
// report past its 30 days; Delete removes it now, after a confirm. The line
// under the title says the rule and how much room all reports take.

/** "Made 2 h ago · 184 KB · Deletes Dec 18". */
function metaLine(report: JarvisReport, now: Date): string {
  return [`Made ${ago(report.created, now)}`, sizeText(report.bytes), endText(report, now)].join(' · ')
}

/** The panel. Shows a plain note when Jarvis doesn't report his reports yet. */
export function ReportsPanel({ reports, now }: { reports: JarvisReports | null; now: Date }) {
  const { mutate } = useSWRConfig()
  // The id of the report whose Keep switch is being saved, so its row can block.
  const [savingId, setSavingId] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<JarvisReport | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [note, setNote] = useState('')

  /** Switches Keep on or off for one report. */
  async function setKept(report: JarvisReport, keep: boolean) {
    setSavingId(report.id)
    const result = await changeReport({ op: 'keep', id: report.id, keep })
    await mutate(SNAPSHOT_KEY)
    setSavingId(null)
    setNote(`${report.title}: ${result.message}`)
  }

  /** Deletes the report the confirm dialog is about. */
  async function remove() {
    if (!deleting) return
    setDeleteBusy(true)
    setDeleteError(null)
    const result = await changeReport({ op: 'delete', id: deleting.id })
    if (!result.ok) {
      setDeleteBusy(false)
      setDeleteError(result.message)
      return
    }
    await mutate(SNAPSHOT_KEY)
    setDeleteBusy(false)
    setNote(`Deleted “${deleting.title}”`)
    setDeleting(null)
  }

  if (reports === null) {
    return (
      <section className="glass panel" aria-labelledby="reports-title">
        <h2 id="reports-title" className="panel__title">Reports</h2>
        <p className="empty">Jarvis isn’t listing his reports right now.</p>
      </section>
    )
  }

  return (
    <section className="glass panel reports" aria-labelledby="reports-title">
      <header className="panel__head">
        <div>
          <h2 id="reports-title" className="panel__title">Reports</h2>
          <p className="panel__sub">{rulesText(reports)}</p>
        </div>
      </header>
      {reports.reports.length === 0 ? (
        <p className="empty">No reports yet. Ask Jarvis for a report at the end of a long task and it shows up here.</p>
      ) : (
        <ul className="cloud__list reports__list">
          {reports.reports.map((r) => {
            const busy = savingId === r.id
            return (
              <li key={r.id} className="reports__item" aria-busy={busy}>
                <div className="reports__text">
                  <a className="reports__title" href={reportHref(r.id)} target="_blank" rel="noreferrer">{r.title}</a>
                  {r.summary ? <p className="loaded__role">{r.summary}</p> : null}
                  <p className="cloud__meta loaded__meta">{metaLine(r, now)}</p>
                </div>
                <div className="reports__controls">
                  <button type="button" role="switch" aria-checked={r.kept} aria-label={`Keep ${r.title}`} className="switch reports__keep" disabled={busy} onClick={() => void setKept(r, !r.kept)}>
                    <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
                    <span className="reports__keep-word" aria-hidden="true">Keep</span>
                  </button>
                  <button type="button" className="btn btn--quiet" aria-label={`Delete ${r.title}`} disabled={busy} onClick={() => { setDeleteError(null); setDeleting(r) }}>Delete</button>
                </div>
                {busy ? <div className="reports__block"><Spinner label="Saving…" /></div> : null}
              </li>
            )
          })}
        </ul>
      )}
      {note ? <p className="cloud__foot" role="status">{note}</p> : null}
      {deleting ? (
        <ConfirmDialog
          title="Delete this report?"
          body={`“${deleting.title}” is removed from the PC for good.`}
          confirmLabel="Delete"
          busyLabel="Deleting…"
          busy={deleteBusy}
          error={deleteError}
          onConfirm={() => void remove()}
          onClose={() => setDeleting(null)}
        />
      ) : null}
    </section>
  )
}
