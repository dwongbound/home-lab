import { useEffect, useRef } from 'react'
import { Spinner } from './Spinner'

interface Props {
  title: string
  body: string
  confirmLabel: string
  busyLabel: string
  busy: boolean
  error: string | null
  onConfirm: () => void
  onClose: () => void
}

// A confirm dialog for actions that change the PC. Native <dialog>, so focus
// trapping and Esc come from the browser. It has a fixed height so it doesn't
// jump when an error appears. While the action runs it is blocked: both
// buttons disabled, Esc ignored and a spinner over the top.

/** The dialog. Mount it to open it; unmount it to close it. */
export function ConfirmDialog({ title, body, confirmLabel, busyLabel, busy, error, onConfirm, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null)

  // Open as a modal on mount. showModal is optional-chained because jsdom
  // (the unit test DOM) doesn't implement it.
  useEffect(() => {
    const d = ref.current
    if (d && !d.open) d.showModal?.()
    return () => d?.close?.()
  }, [])

  return (
    <dialog
      ref={ref}
      className="dialog glass"
      aria-labelledby="dialog-title"
      aria-busy={busy}
      // Esc fires "cancel". Stop the browser closing it on its own so React
      // stays in charge, and ignore Esc while the action is running.
      onCancel={(e) => {
        e.preventDefault()
        if (!busy) onClose()
      }}
    >
      <h2 id="dialog-title" className="dialog__title">{title}</h2>
      <p className="dialog__body">{body}</p>
      {error ? <p className="dialog__error" role="alert">{error}</p> : null}
      <div className="dialog__actions">
        <button type="button" className="btn btn--quiet" onClick={onClose} disabled={busy}>Close</button>
        <button type="button" className="btn btn--primary" onClick={onConfirm} disabled={busy}>{confirmLabel}</button>
      </div>
      {busy ? <div className="dialog__block"><Spinner label={busyLabel} /></div> : null}
    </dialog>
  )
}
