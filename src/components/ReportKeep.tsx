import { Icon } from './Icon'
import { useState } from 'react'
import { useSWRConfig } from 'swr'
import { SNAPSHOT_KEY, changeReport } from '../api/client'
import { KEEP_CHOICES, keepChange, keepLabel, reportFile, reportHref } from '../lib/reports'
import type { JarvisReport } from '../types'
import { Spinner } from './Spinner'

// How long one report is kept, as a plain dropdown that reads "Keep 2 weeks"
// (the usual), and a Share button beside it (Dylan, 2026-11-19: one simple
// selector, not a pop-up). Used on each row of the Reports panel and at the
// bottom left of an open report.

/** The dropdown's value for a number of days; "forever" when it's kept for good. */
function valueOf(days: number | null): string {
  if (days === null) return 'forever'
  return String(days)
}

/** The dropdown. Saves a new choice as soon as it's picked, blocked with a label while it saves. */
export function ReportKeepSelect({ report }: { report: JarvisReport }) {
  const { mutate } = useSWRConfig()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  let current: number | null = report.keepDays
  if (report.kept) current = null
  // A length Jarvis set that isn't one of the choices still needs a line of its own.
  const choices: (number | null)[] = [...KEEP_CHOICES]
  if (current !== null && !choices.includes(current)) choices.unshift(current)

  /** Sends the picked length to Jarvis and refreshes the list. */
  async function pick(value: string) {
    const days = KEEP_CHOICES.find((choice) => valueOf(choice) === value)
    if (days === undefined) return
    setBusy(true)
    setError(null)
    const result = await changeReport(keepChange(report.id, days))
    await mutate(SNAPSHOT_KEY)
    setBusy(false)
    if (!result.ok) setError(result.message)
  }

  return (
    <span className="keep" aria-busy={busy}>
      <select className="keep__select" aria-label={`How long to keep ${report.title}`} value={valueOf(current)} disabled={busy} onChange={(e) => void pick(e.target.value)}>
        {choices.map((days) => <option key={valueOf(days)} value={valueOf(days)}>{keepLabel(days)}</option>)}
      </select>
      {busy ? <span className="keep__block"><Spinner label="Saving…" /></span> : null}
      {error ? <span className="keep__error" role="alert">{error}</span> : null}
    </span>
  )
}

/**
 * Share: hands the report, as its one HTML file, to the phone's share sheet
 * (Save to Files, Messages). Where the browser can't share a file, it
 * downloads the file instead. Drawn as Apple's share mark (Dylan, 2026-11-19);
 * a word beside it only while it fetches or when it fails.
 */
export function ReportShareButton({ id, title }: { id: string; title: string }) {
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState(false)

  /** Fetches the report and shares or downloads it. */
  async function share() {
    setBusy(true)
    setFailed(false)
    try {
      const res = await fetch(reportHref(id))
      if (!res.ok) throw new Error('gone')
      const file = new File([await res.blob()], reportFile(title), { type: 'text/html' })
      if (typeof navigator.canShare === 'function' && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title })
      } else {
        const link = document.createElement('a')
        link.href = URL.createObjectURL(file)
        link.download = file.name
        link.click()
        URL.revokeObjectURL(link.href)
      }
    } catch (err) {
      // Closing the share sheet without sending isn't a failure.
      if (!(err instanceof DOMException && err.name === 'AbortError')) setFailed(true)
    }
    setBusy(false)
  }

  let status = ''
  if (busy) status = 'Getting it…'
  if (failed) status = 'Couldn’t share'
  return (
    <span className="share">
      <button type="button" className="icon-btn" aria-label={`Share ${title}`} disabled={busy} onClick={() => void share()}><Icon name="share" /></button>
      {status ? <span className="share__status" role="status">{status}</span> : null}
    </span>
  )
}
