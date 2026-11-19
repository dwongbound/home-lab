import { useState } from 'react'
import { useSWRConfig } from 'swr'
import { SNAPSHOT_KEY, changeReport } from '../api/client'
import { ago } from '../lib/format'
import { openReport } from '../lib/reportViewer'
import { endText, reportHref, rulesText, sizeText } from '../lib/reports'
import type { JarvisReport, JarvisReports } from '../types'
import { ConfirmDialog } from './ConfirmDialog'
import { ReportKeepSelect, ReportShareButton } from './ReportKeep'

// Reports (Dylan, 2026-11-18): the pages Jarvis writes when a long task
// ends in more than a chat reply can hold. Each row opens the report in the
// viewer (ReportViewer) and says how big it is and when Jarvis deletes it. A
// plain dropdown says how long the report is kept ("Keep 2 weeks", the usual)
// and changes it, with Share beside it (ReportKeep; Dylan, 2026-11-19).
// Delete removes it now, after a confirm. The line under the
// title says the rule and how much room all reports take.

/** "Made 2 h ago · 184 KB · Deletes Dec 18". */
function metaLine(report: JarvisReport, now: Date): string {
  return [`Made ${ago(report.created, now)}`, sizeText(report.bytes), endText(report, now)].join(' · ')
}

/** The panel. Shows a plain note when Jarvis doesn't report his reports yet. */
export function ReportsPanel({ reports, now }: { reports: JarvisReports | null; now: Date }) {
  const { mutate } = useSWRConfig()
  const [deleting, setDeleting] = useState<JarvisReport | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [note, setNote] = useState('')

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
            return (
              <li key={r.id} className="reports__item">
                <div className="reports__text">
                  {/* A real link (so it can still be copied), but a tap opens the report here in the viewer. */}
                  <a className="reports__title" href={reportHref(r.id)} onClick={(e) => { e.preventDefault(); openReport(r.id, r.title) }}>{r.title}</a>
                  {r.summary ? <p className="loaded__role reports__summary">{r.summary}</p> : null}
                  <p className="cloud__meta loaded__meta">{metaLine(r, now)}</p>
                </div>
                <div className="reports__controls">
                  <ReportKeepSelect report={r} />
                  <ReportShareButton id={r.id} title={r.title} />
                  <button type="button" className="btn btn--quiet" aria-label={`Delete ${r.title}`} onClick={() => { setDeleteError(null); setDeleting(r) }}>Delete</button>
                </div>
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
