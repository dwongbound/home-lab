import { useState } from 'react'
import { changeRoutine, useRoutines } from '../api/client'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { RoutineEditor } from '../components/RoutineEditor'
import { Spinner } from '../components/Spinner'
import { ago } from '../lib/format'
import { actionLine, blankRoutine, triggerLine } from '../lib/routines'
import type { Routine, RoutineDraft } from '../types'

// The Routines page (Dylan, 2026-11-18): groups of steps Jarvis runs by
// himself at a set time, when you get home or leave, or when you go to
// sleep or wake up, like Apple's Shortcuts but living in Jarvis. Each row
// has an on/off switch, Run (now, whatever its trigger) and Edit; New
// routine opens the same editor empty. Jarvis keeps and runs them; this
// page only reads and changes the list.

/** How a routine's last run went, in a few words. */
function lastRunLine(routine: Routine, now: Date): string {
  if (!routine.lastRun) return 'Hasn’t run yet'
  const when = ago(routine.lastRun.at, now)
  if (routine.lastRun.ok) return `Last ran ${when}`
  return `Last run ${when} had trouble: ${routine.lastRun.detail}`
}

/** The page. */
export function Routines({ now }: { now: Date }) {
  const { data: book, error, isLoading, mutate } = useRoutines()
  // The routine open in the editor: a blank one for New, a copy for Edit.
  const [editing, setEditing] = useState<RoutineDraft | null>(null)
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<Routine | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  // The id of the routine being run or switched right now, so its row can block.
  const [working, setWorking] = useState<{ id: string; label: string } | null>(null)
  const [note, setNote] = useState('')

  /** Saves what the editor holds, then closes it. */
  async function save(draft: RoutineDraft) {
    setSaving(true)
    setSaveError(null)
    const result = await changeRoutine({ op: 'save', routine: draft })
    setSaving(false)
    if (!result.ok) {
      setSaveError(result.message)
      return
    }
    setEditing(null)
    setNote(`Saved “${draft.name}”`)
    await mutate()
  }

  /** Turns one routine on or off. */
  async function setEnabled(routine: Routine, enabled: boolean) {
    setWorking({ id: routine.id, label: 'Saving…' })
    const { lastRun: _lastRun, ...draft } = routine
    const result = await changeRoutine({ op: 'save', routine: { ...draft, enabled } })
    setWorking(null)
    setNote(result.ok ? `“${routine.name}” is ${enabled ? 'on' : 'off'}` : result.message)
    await mutate()
  }

  /** Runs one routine now, whatever its trigger. */
  async function run(routine: Routine) {
    setWorking({ id: routine.id, label: 'Running…' })
    const result = await changeRoutine({ op: 'run', id: routine.id })
    setWorking(null)
    setNote(`${routine.name}: ${result.message}`)
    await mutate()
  }

  /** Deletes the routine the confirm dialog is about. */
  async function remove() {
    if (!deleting) return
    setDeleteBusy(true)
    setDeleteError(null)
    const result = await changeRoutine({ op: 'delete', id: deleting.id })
    setDeleteBusy(false)
    if (!result.ok) {
      setDeleteError(result.message)
      return
    }
    setNote(`Deleted “${deleting.name}”`)
    setDeleting(null)
    await mutate()
  }

  let body
  if (isLoading) {
    body = <div className="memory__wait"><Spinner label="Asking Jarvis…" /></div>
  } else if (error || book === null || book === undefined) {
    body = <p className="empty">Jarvis isn’t answering, so his routines can’t be shown right now. Open this page through Tailscale, with Jarvis running on the PC.</p>
  } else if (book.routines.length === 0) {
    body = <p className="empty">No routines yet. Make one for bedtime, getting home, or a time of day.</p>
  } else {
    body = (
      <ul className="routines" aria-label="Routines">
        {book.routines.map((r) => {
          const busy = working?.id === r.id
          return (
            <li key={r.id} className="routines__row" data-off={r.enabled ? undefined : ''} aria-busy={busy}>
              <div className="routines__text">
                <p className="routines__name">{r.name}</p>
                <p className="routines__when">{triggerLine(r.trigger)}</p>
                <p className="routines__steps">{r.actions.map((a) => actionLine(a, book.options)).join(' · ')}</p>
                <p className="memory__meta">{lastRunLine(r, now)}</p>
              </div>
              <div className="routines__controls">
                <button type="button" role="switch" aria-checked={r.enabled} aria-label={`${r.name} on`} className="switch routines__switch" disabled={busy} onClick={() => void setEnabled(r, !r.enabled)}>
                  <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
                </button>
                <button type="button" className="btn" aria-label={`Run ${r.name}`} disabled={busy} onClick={() => void run(r)}>Run</button>
                <button type="button" className="btn btn--quiet" aria-label={`Edit ${r.name}`} disabled={busy} onClick={() => { const { lastRun: _lastRun, ...draft } = r; setSaveError(null); setEditing(draft) }}>Edit</button>
              </div>
              {busy ? <div className="routines__block"><Spinner label={working.label} /></div> : null}
            </li>
          )
        })}
      </ul>
    )
  }

  const known = editing?.id ? book?.routines.find((r) => r.id === editing.id) : undefined
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Routines</h1></section>
      <section className="glass panel" aria-labelledby="routines-title">
        <div className="panel__head">
          <div>
            <h2 id="routines-title" className="panel__title">Your routines</h2>
            <p className="panel__sub">Steps Jarvis runs by himself: at a time, when you come and go, or when you go to sleep.</p>
          </div>
          <button type="button" className="btn btn--primary routines__new" disabled={!book} onClick={() => { setSaveError(null); setEditing(blankRoutine()) }}>New routine</button>
        </div>
        {body}
        <p className="cloud__foot" role="status">{note}</p>
      </section>

      {editing && book ? (
        <RoutineEditor
          start={editing}
          options={book.options}
          busy={saving}
          error={saveError}
          onSave={(draft) => void save(draft)}
          onDelete={known ? () => { setEditing(null); setDeleteError(null); setDeleting(known) } : undefined}
          onClose={() => setEditing(null)}
        />
      ) : null}
      {deleting ? (
        <ConfirmDialog
          title="Delete this routine?"
          body={`“${deleting.name}” will stop running and can’t be brought back.`}
          confirmLabel="Delete"
          busyLabel="Deleting…"
          busy={deleteBusy}
          error={deleteError}
          onConfirm={() => void remove()}
          onClose={() => setDeleting(null)}
        />
      ) : null}
    </>
  )
}
