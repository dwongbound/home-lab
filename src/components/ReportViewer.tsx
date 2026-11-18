import { useEffect, useRef, useState } from 'react'
import { closeReport, useOpenReport, type OpenReport } from '../lib/reportViewer'
import { reportHref } from '../lib/reports'
import { useScrollLock } from '../useScrollLock'
import { Spinner } from './Spinner'

// A report, opened inside Jarvis (Dylan, 2026-11-18: "the reports should
// open from within the jarvis app and not link somewhere"). The report is
// Jarvis's own HTML in a frame that can't run scripts or reach this page
// (the frame is sandboxed, and the server sends the same rule with it). The
// box is a fixed size; the report scrolls inside it. Mounted once per page
// (App and the /talk page) and shown whenever openReport is called.

/** The dialog for one open report. */
function ReportDialog({ report }: { report: OpenReport }) {
  const ref = useRef<HTMLDialogElement>(null)
  const [loaded, setLoaded] = useState(false)
  useScrollLock()

  // Open as a modal on mount, above the chat sheet when that's open. jsdom
  // (the unit test DOM) has no showModal, so there it's just marked open.
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    // Hold focus on the box itself so no button shows a focus ring on open (Safari).
    d.focus()
    return () => { if (typeof d.close === 'function') d.close() }
  }, [])

  return (
    <dialog
      ref={ref}
      className="dialog dialog--report glass"
      tabIndex={-1}
      aria-labelledby="report-title"
      // Esc fires "cancel"; React closes it so the store stays in step.
      onCancel={(e) => { e.preventDefault(); closeReport() }}
      // A tap on the dimmed backdrop (outside the box) closes it too.
      onClick={(e) => { if (e.target === e.currentTarget) closeReport() }}
    >
      <h2 id="report-title" className="dialog__title report__title">{report.title}</h2>
      <div className="report__frame-box" aria-busy={!loaded}>
        {/* sandbox with no allowances: no scripts, no forms, and an origin of its own. */}
        <iframe className="report__frame" title={report.title} src={reportHref(report.id)} sandbox="" onLoad={() => setLoaded(true)} />
        {loaded ? null : <div className="report__wait"><Spinner label="Opening the report…" /></div>}
      </div>
      <div className="dialog__actions">
        <button type="button" className="btn btn--primary" onClick={closeReport}>Close</button>
      </div>
    </dialog>
  )
}

/** Shows the open report, if there is one. Keyed by id so a new report starts fresh. */
export function ReportViewer() {
  const report = useOpenReport()
  if (report === null) return null
  return <ReportDialog key={report.id} report={report} />
}
