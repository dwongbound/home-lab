import { useEffect, useRef, useState } from 'react'
import { ACTION_CHOICES, DAYS, TRIGGER_CHOICES, blankAction, blankTrigger, commandLabel, commandTakesValue, commandTakesWords, routineProblem } from '../lib/routines'
import type { RoutineAction, RoutineDay, RoutineDraft, RoutineOptions, RoutineTrigger } from '../types'
import { useScrollLock } from '../useScrollLock'
import { Spinner } from './Spinner'

// The pop-up where a routine is written: its name, when it runs, and its
// steps in order. Native <dialog> at a fixed size; the steps scroll inside
// it. Nothing is saved until Save, and while Jarvis is saving the whole
// box is blocked with a labelled spinner.

interface Props {
  /** The routine being edited, or a blank one. */
  start: RoutineDraft
  options: RoutineOptions
  busy: boolean
  /** Why the last Save didn't take, if it didn't. */
  error: string | null
  onSave: (draft: RoutineDraft) => void
  /** Only for a routine that already exists. */
  onDelete?: () => void
  onClose: () => void
}

/** The editor. Mount it to open it; unmount it to close it. */
export function RoutineEditor({ start, options, busy, error, onSave, onDelete, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const [draft, setDraft] = useState<RoutineDraft>(start)
  // Shown only after a Save that couldn't go, so the box doesn't nag while it's being filled in.
  const [problem, setProblem] = useState<string | null>(null)
  useScrollLock()

  // Open as a modal on mount. jsdom (the unit test DOM) has no showModal.
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    d.focus()
    return () => { if (typeof d.close === 'function') d.close() }
  }, [])

  /** Replaces the step at one place in the list. */
  function setAction(index: number, action: RoutineAction) {
    setDraft((d) => ({ ...d, actions: d.actions.map((a, i) => (i === index ? action : a)) }))
  }

  /** Moves a step one place up (-1) or down (+1). */
  function moveAction(index: number, by: -1 | 1) {
    setDraft((d) => {
      const to = index + by
      if (to < 0 || to >= d.actions.length) return d
      const actions = [...d.actions]
      const [moved] = actions.splice(index, 1)
      actions.splice(to, 0, moved)
      return { ...d, actions }
    })
  }

  /** Checks the routine and hands it up, or says what's missing. */
  function save() {
    const missing = routineProblem(draft)
    setProblem(missing)
    if (missing === null) onSave({ ...draft, name: draft.name.trim() })
  }

  return (
    <dialog
      ref={ref}
      className="dialog dialog--detail dialog--routine glass"
      tabIndex={-1}
      aria-labelledby="routine-title"
      aria-busy={busy}
      // Esc fires "cancel"; ignored while Jarvis is saving.
      onCancel={(e) => { e.preventDefault(); if (!busy) onClose() }}
    >
      <header className="detail__head">
        <h2 id="routine-title" className="dialog__title">{start.id ? 'Edit routine' : 'New routine'}</h2>
      </header>
      <div className="detail__body routine__form">
        <label className="field">
          <span className="field__label">Name</span>
          <input className="field__box" value={draft.name} maxLength={60} placeholder="Bedtime" autoComplete="off" onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
        </label>

        <label className="field">
          <span className="field__label">When</span>
          <select className="field__box" value={draft.trigger.type} onChange={(e) => setDraft({ ...draft, trigger: blankTrigger(e.target.value as RoutineTrigger['type']) })}>
            {TRIGGER_CHOICES.map((c) => <option key={c.type} value={c.type}>{c.label}</option>)}
          </select>
        </label>
        <TriggerFields trigger={draft.trigger} onChange={(trigger) => setDraft({ ...draft, trigger })} />

        <h3 className="routine__heading">Then</h3>
        {draft.actions.length === 0 ? <p className="routine__hint">No steps yet. Add the first one below.</p> : null}
        <ol className="routine__steps">
          {draft.actions.map((action, i) => (
            <li key={i} className="routine__step" aria-label={`Step ${i + 1}`}>
              <div className="routine__stephead">
                <span className="routine__num">{i + 1}</span>
                <span className="routine__kind">{ACTION_CHOICES.find((c) => c.type === action.type)?.label}</span>
                <button type="button" className="btn btn--quiet routine__mini" aria-label={`Move step ${i + 1} up`} disabled={i === 0} onClick={() => moveAction(i, -1)}>↑</button>
                <button type="button" className="btn btn--quiet routine__mini" aria-label={`Move step ${i + 1} down`} disabled={i === draft.actions.length - 1} onClick={() => moveAction(i, 1)}>↓</button>
                <button type="button" className="btn btn--quiet routine__mini" aria-label={`Remove step ${i + 1}`} onClick={() => setDraft({ ...draft, actions: draft.actions.filter((_, j) => j !== i) })}>✕</button>
              </div>
              <ActionFields action={action} options={options} onChange={(next) => setAction(i, next)} />
            </li>
          ))}
        </ol>
        <label className="field">
          <span className="field__label">Add a step</span>
          {/* Picking a kind adds the step and the box goes back to its prompt. */}
          <select
            className="field__box"
            value=""
            onChange={(e) => {
              const type = e.target.value as RoutineAction['type']
              if (type) setDraft({ ...draft, actions: [...draft.actions, blankAction(type, options)] })
            }}
          >
            <option value="">Choose what happens…</option>
            {ACTION_CHOICES.map((c) => <option key={c.type} value={c.type}>{c.label}</option>)}
          </select>
        </label>
        {problem || error ? <p className="dialog__error" role="alert">{problem ?? error}</p> : null}
      </div>
      <div className="dialog__actions">
        {onDelete ? <button type="button" className="btn btn--quiet routine__delete" onClick={onDelete} disabled={busy}>Delete</button> : null}
        <button type="button" className="btn btn--quiet" onClick={onClose} disabled={busy}>Close</button>
        <button type="button" className="btn btn--primary" onClick={save} disabled={busy}>Save</button>
      </div>
      {busy ? <div className="dialog__block"><Spinner label="Saving…" /></div> : null}
    </dialog>
  )
}

/** The extra boxes a trigger needs: a time and days, or how long away counts. */
function TriggerFields({ trigger, onChange }: { trigger: RoutineTrigger; onChange: (t: RoutineTrigger) => void }) {
  if (trigger.type === 'time') {
    /** Adds or removes one day. */
    const toggleDay = (day: RoutineDay) => {
      const days = trigger.days.includes(day) ? trigger.days.filter((d) => d !== day) : [...trigger.days, day]
      onChange({ ...trigger, days })
    }
    return (
      <>
        <label className="field">
          <span className="field__label">Time</span>
          <input className="field__box" type="time" value={trigger.at} onChange={(e) => onChange({ ...trigger, at: e.target.value })} />
        </label>
        <div className="field">
          <span className="field__label" id="routine-days">Days</span>
          <div className="routine__days" role="group" aria-labelledby="routine-days">
            {DAYS.map((d) => (
              <button key={d.id} type="button" className="segmented__opt" aria-pressed={trigger.days.includes(d.id)} onClick={() => toggleDay(d.id)}>{d.label}</button>
            ))}
          </div>
          <span className="routine__hint">None picked means every day.</span>
        </div>
      </>
    )
  }
  if (trigger.type === 'arrive') {
    return (
      <label className="field">
        <span className="field__label">Only after being away at least (minutes)</span>
        <input className="field__box" type="number" min={0} max={1440} inputMode="numeric" value={trigger.minAway} onChange={(e) => onChange({ ...trigger, minAway: Number(e.target.value) || 0 })} />
      </label>
    )
  }
  if (trigger.type === 'asleep') return <p className="routine__hint">Runs when night mode turns on, from the Apple TV’s Night button or your Sleep Focus.</p>
  if (trigger.type === 'awake') return <p className="routine__hint">Runs when you’re marked awake: leaving night mode, or the first time you talk to Jarvis.</p>
  return null
}

/** The boxes one step needs, by its kind. */
function ActionFields({ action, options, onChange }: { action: RoutineAction; options: RoutineOptions; onChange: (a: RoutineAction) => void }) {
  if (action.type === 'device') {
    const device = options.devices.find((d) => d.entity === action.entity)
    const commands = device?.commands ?? [action.command]
    return (
      <div className="routine__fields">
        <select className="field__box" aria-label="Device" value={action.entity} onChange={(e) => {
          const next = options.devices.find((d) => d.entity === e.target.value)
          onChange({ type: 'device', entity: e.target.value, command: next?.commands[0] ?? 'turn_off' })
        }}>
          {device ? null : <option value={action.entity}>{action.entity || 'Pick a device'}</option>}
          {options.devices.map((d) => <option key={d.entity} value={d.entity}>{d.name}</option>)}
        </select>
        <select className="field__box" aria-label="What to do" value={action.command} onChange={(e) => onChange({ type: 'device', entity: action.entity, command: e.target.value })}>
          {commands.map((c) => <option key={c} value={c}>{commandLabel(c)}</option>)}
        </select>
        {commandTakesValue(action.command) ? (
          <input className="field__box" aria-label="Value" value={action.value ?? ''} placeholder={valueHint(action.command)} onChange={(e) => onChange({ ...action, value: valueOf(action.command, e.target.value) })} />
        ) : null}
      </div>
    )
  }
  if (action.type === 'scene') {
    return (
      <select className="field__box" aria-label="Scene" value={action.entity} onChange={(e) => onChange({ type: 'scene', entity: e.target.value })}>
        {options.scenes.some((s) => s.entity === action.entity) ? null : <option value={action.entity}>{action.entity || 'Pick a scene'}</option>}
        {options.scenes.map((s) => <option key={s.entity} value={s.entity}>{s.name}</option>)}
      </select>
    )
  }
  if (action.type === 'app') {
    const screen = options.apps.find((a) => a.entity === action.entity)
    const apps = screen?.apps ?? [action.app]
    return (
      <div className="routine__fields">
        <select className="field__box" aria-label="TV" value={action.entity} onChange={(e) => {
          const next = options.apps.find((a) => a.entity === e.target.value)
          onChange({ type: 'app', entity: e.target.value, app: next?.apps[0] ?? '' })
        }}>
          {screen ? null : <option value={action.entity}>{action.entity || 'Pick a TV'}</option>}
          {options.apps.map((a) => <option key={a.entity} value={a.entity}>{a.name}</option>)}
        </select>
        <select className="field__box" aria-label="App" value={action.app} onChange={(e) => onChange({ ...action, app: e.target.value })}>
          {apps.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
      </div>
    )
  }
  if (action.type === 'notify') {
    return <input className="field__box" aria-label="Notification text" value={action.text} maxLength={300} placeholder="Time to head out" onChange={(e) => onChange({ ...action, text: e.target.value })} />
  }
  if (action.type === 'ask') {
    return (
      <>
        <textarea className="field__box field__box--tall" aria-label="What Jarvis should do" value={action.text} maxLength={2000} placeholder="Tell me tomorrow’s first meeting and the weather" onChange={(e) => onChange({ ...action, text: e.target.value })} />
        <ConfirmSwitch on={action.confirm} onChange={(confirm) => onChange({ ...action, confirm })} />
      </>
    )
  }
  if (action.type === 'email') {
    return (
      <>
        <input className="field__box" type="text" inputMode="email" aria-label="To" value={action.to} placeholder="someone@example.com, another@example.com" autoComplete="off" onChange={(e) => onChange({ ...action, to: e.target.value })} />
        <input className="field__box" aria-label="Subject" value={action.subject} maxLength={200} placeholder="Subject" onChange={(e) => onChange({ ...action, subject: e.target.value })} />
        <textarea className="field__box field__box--tall" aria-label="Message" value={action.body} maxLength={5000} placeholder="Message" onChange={(e) => onChange({ ...action, body: e.target.value })} />
        <ConfirmSwitch on={action.confirm} onChange={(confirm) => onChange({ ...action, confirm })} />
      </>
    )
  }
  return (
    <label className="routine__fields routine__fields--inline">
      <input className="field__box" type="number" min={1} max={600} inputMode="numeric" aria-label="Seconds to wait" value={action.seconds} onChange={(e) => onChange({ type: 'wait', seconds: Number(e.target.value) || 0 })} />
      <span className="routine__hint">seconds</span>
    </label>
  )
}

/** What to show in an empty value box, by command. */
function valueHint(command: string): string {
  if (command === 'set_hvac_mode') return 'heat'
  if (command === 'select_source') return 'Netflix'
  if (command === 'volume_set') return '0.3'
  return '68'
}

/** A typed value for a device command: a number for volumes and temperatures, words for a mode or an app. */
function valueOf(command: string, typed: string): number | string | undefined {
  if (typed.trim() === '') return undefined
  if (commandTakesWords(command)) return typed
  const number = Number(typed)
  return Number.isFinite(number) ? number : typed
}

/** "Ask me first": whether Jarvis checks with you before this step runs. */
function ConfirmSwitch({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <button type="button" role="switch" aria-checked={on} className="switch routine__confirm" onClick={() => onChange(!on)}>
      <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
      <span>Ask me first, each time</span>
    </button>
  )
}
