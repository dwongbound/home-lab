import { useEffect, useRef } from 'react'
import { KEEP_CHOICES, endText, keepLabel, reportHref } from '../lib/reports'
import type { JarvisReport } from '../types'
import { useScrollLock } from '../useScrollLock'
import { Spinner } from './Spinner'

interface Props {
  report: JarvisReport
  now: Date
  /** True while a new keep time is being saved. */
  busy: boolean
  error: string | null
  /** Called with the days picked; null = keep for good. */
  onPick: (days: 14 | 30 | 90 | null) => void
  onClose: () => void
}

// What opens from a report's "Keep 2 weeks" button (Dylan, 2026-11-19): how
// long to keep this one report, and two ways to take it elsewhere: Save a
// copy (the report's one HTML file, into Files or Downloads) and Share (the
// phone's share sheet, so it can go out by text). A fixed-size native
// <dialog>, blocked with a spinner while a choice is saved.

/** A file name made from the report's title: "Bookshelf speakers under 400.html". */
function fileName(title: string): string {
  const plain = title.replace(/[^\w -]+/g, '').trim().slice(0, 60)
  return `${plain || 'report'}.html`
}

/** True when this browser has a share sheet to hand the report to. */
function canShare(): boolean {
  return typeof navigator !== 'undefined' && typeof navigator.share === 'function'
}

/** The dialog. Mount it to open it; unmount it to close it. */
export function ReportKeepDialog({ report, now, busy, error, onPick, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  useScrollLock()

  // Open as a modal on mount (optional-chained: jsdom has no showModal).
  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal?.()
    // Focus the box, not its first button, so no focus ring shows on open (Safari).
    d?.focus()
    return () => d?.close?.()
  }, [])

  /** Hands the report's own page to the share sheet; closing the sheet without sending is not an error. */
  async function share() {
    try {
      await navigator.share({ title: report.title, url: new URL(reportHref(report.id), window.location.origin).href })
    } catch {
      // He closed the sheet, or the browser refused; nothing to do.
    }
  }

  let current: number | null = report.keepDays
  if (report.kept) current = null

  return (
    <dialog
      ref={ref}
      className="dialog dialog--keep glass"
      tabIndex={-1}
      aria-labelledby="keep-title"
      aria-busy={busy}
      // Esc fires "cancel": React stays in charge of closing, and Esc is ignored while saving.
      onCancel={(e) => {
        e.preventDefault()
        if (!busy) onClose()
      }}
    >
      <div>
        <h2 id="keep-title" className="dialog__title">{report.title}</h2>
        <p className="dialog__body">{endText(report, now)}</p>
      </div>
      <div className="keep__body">
        <ul className="keep__choices" aria-label="How long to keep it">
          {KEEP_CHOICES.map((days) => (
            <li key={String(days)}>
              <button type="button" className="btn btn--wide keep__choice" aria-pressed={days === current} disabled={busy} onClick={() => onPick(days)}>
                {keepLabel(days)}
              </button>
            </li>
          ))}
        </ul>
        <div className="keep__share">
          <a className="btn keep__link" href={reportHref(report.id)} download={fileName(report.title)}>Save a copy</a>
          {canShare() ? <button type="button" className="btn" onClick={() => void share()}>Share</button> : null}
        </div>
        {error ? <p className="dialog__error" role="alert">{error}</p> : null}
      </div>
      <div className="dialog__actions">
        <button type="button" className="btn btn--quiet" onClick={onClose} disabled={busy}>Close</button>
      </div>
      {busy ? <div className="dialog__block"><Spinner label="Saving…" /></div> : null}
    </dialog>
  )
}
