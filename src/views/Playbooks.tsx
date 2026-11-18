import { useState } from 'react'
import { changePlaybook, usePlaybooks } from '../api/client'
import { ConfirmDialog } from '../components/ConfirmDialog'
import { PlaybookEditor } from '../components/PlaybookEditor'
import { Spinner } from '../components/Spinner'
import { ago } from '../lib/format'
import { blankPlaybook, draftOf, failedChecks, stepLine, triggerLine } from '../lib/playbooks'
import type { Playbook, PlaybookDraft } from '../types'

// The Playbooks page (Dylan, 2026-11-18): the jobs Jarvis knows how to do.
// A playbook is what a job is for, when it runs (a set time, getting home
// or leaving, going to sleep or waking, or only when asked), its steps, and
// a done checklist he checks himself against after every run. Fixed steps
// (lights, the TV) run as plain code; steps in your own words are worked
// out by Jarvis. Each row has an on/off switch, Run (now, whatever its
// trigger) and Edit; New playbook opens the same editor empty. Jarvis also
// writes them by interviewing you in chat or Talk. He keeps and runs them;
// this page only reads and changes the list.

/** How a playbook's last run went, in a few words. */
function lastRunLine(playbook: Playbook, now: Date): string {
  if (!playbook.lastRun) return 'Hasn’t run yet'
  const when = ago(playbook.lastRun.at, now)
  if (playbook.lastRun.ok) return `Last ran ${when}`
  return `Last run ${when} had trouble: ${playbook.lastRun.detail}`
}

/** The page. */
export function Playbooks({ now }: { now: Date }) {
  const { data: book, error, isLoading, mutate } = usePlaybooks()
  // The playbook open in the editor: a blank one for New, a copy for Edit.
  const [editing, setEditing] = useState<PlaybookDraft | null>(null)
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<Playbook | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  // The id of the playbook being run or switched right now, so its row can block.
  const [working, setWorking] = useState<{ id: string; label: string } | null>(null)
  const [note, setNote] = useState('')

  /** Saves what the editor holds, then closes it. */
  async function save(draft: PlaybookDraft) {
    setSaving(true)
    setSaveError(null)
    const result = await changePlaybook({ op: 'save', playbook: draft })
    setSaving(false)
    if (!result.ok) {
      setSaveError(result.message)
      return
    }
    setEditing(null)
    setNote(`Saved “${draft.name}”`)
    await mutate()
  }

  /** Turns one playbook on or off. */
  async function setEnabled(playbook: Playbook, enabled: boolean) {
    setWorking({ id: playbook.id, label: 'Saving…' })
    const result = await changePlaybook({ op: 'save', playbook: { ...draftOf(playbook), enabled } })
    setWorking(null)
    setNote(result.ok ? `“${playbook.name}” is ${enabled ? 'on' : 'off'}` : result.message)
    await mutate()
  }

  /** Runs one playbook now, whatever its trigger. */
  async function run(playbook: Playbook) {
    setWorking({ id: playbook.id, label: 'Running…' })
    const result = await changePlaybook({ op: 'run', id: playbook.id })
    setWorking(null)
    setNote(`${playbook.name}: ${result.message}`)
    await mutate()
  }

  /** Deletes the playbook the confirm dialog is about. */
  async function remove() {
    if (!deleting) return
    setDeleteBusy(true)
    setDeleteError(null)
    const result = await changePlaybook({ op: 'delete', id: deleting.id })
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
    body = <p className="empty">Jarvis isn’t answering, so his playbooks can’t be shown right now. Open this page through Tailscale, with Jarvis running on the PC.</p>
  } else if (book.playbooks.length === 0) {
    body = <p className="empty">No playbooks yet. Make one here, or tell Jarvis “let’s make a playbook for…” and he’ll interview you.</p>
  } else {
    body = (
      <ul className="playbooks" aria-label="Playbooks">
        {book.playbooks.map((r) => {
          const busy = working?.id === r.id
          return (
            <li key={r.id} className="playbooks__row" data-off={r.enabled ? undefined : ''} aria-busy={busy}>
              <div className="playbooks__text">
                <p className="playbooks__name">{r.name}</p>
                {r.purpose ? <p className="playbooks__purpose">{r.purpose}</p> : null}
                <p className="playbooks__when">{triggerLine(r.trigger)}</p>
                <p className="playbooks__steps">{r.steps.map((a) => stepLine(a, book.options)).join(' · ')}</p>
                <p className="memory__meta">{lastRunLine(r, now)}</p>
                {failedChecks(r).map((line) => <p key={line} className="playbooks__failed">Not done: {line}</p>)}
              </div>
              <div className="playbooks__controls">
                <button type="button" role="switch" aria-checked={r.enabled} aria-label={`${r.name} on`} className="switch playbooks__switch" disabled={busy} onClick={() => void setEnabled(r, !r.enabled)}>
                  <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
                </button>
                <button type="button" className="btn" aria-label={`Run ${r.name}`} disabled={busy} onClick={() => void run(r)}>Run</button>
                <button type="button" className="btn btn--quiet" aria-label={`Edit ${r.name}`} disabled={busy} onClick={() => { setSaveError(null); setEditing(draftOf(r)) }}>Edit</button>
              </div>
              {busy ? <div className="playbooks__block"><Spinner label={working.label} /></div> : null}
            </li>
          )
        })}
      </ul>
    )
  }

  const known = editing?.id ? book?.playbooks.find((r) => r.id === editing.id) : undefined
  return (
    <>
      <section className="hero hero--small"><h1 className="hero__title">Playbooks</h1></section>
      <section className="glass panel" aria-labelledby="playbooks-title">
        <div className="panel__head">
          <div>
            <h2 id="playbooks-title" className="panel__title">Your playbooks</h2>
            <p className="panel__sub">Jobs Jarvis knows how to do: what each is for, when it runs, its steps, and how he checks it’s done.</p>
          </div>
          <button type="button" className="btn btn--primary playbooks__new" disabled={!book} onClick={() => { setSaveError(null); setEditing(blankPlaybook()) }}>New playbook</button>
        </div>
        {body}
        <p className="cloud__foot" role="status">{note}</p>
      </section>

      {editing && book ? (
        <PlaybookEditor
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
          title="Delete this playbook?"
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
