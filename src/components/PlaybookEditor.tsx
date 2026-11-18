import { useEffect, useRef, useState } from 'react'
import { DAYS, STEP_CHOICES, THINKER_CHOICES, TRIGGER_CHOICES, blankStep, blankTrigger, commandLabel, commandTakesValue, commandTakesWords, playbookProblem } from '../lib/playbooks'
import type { PlaybookDay, PlaybookDraft, PlaybookOptions, PlaybookStep, PlaybookThinker, PlaybookTrigger } from '../types'
import { useScrollLock } from '../useScrollLock'
import { Spinner } from './Spinner'

// The pop-up where a playbook is written: its name and purpose, when it
// runs, its steps in order, the checklist that says it's done, and (folded
// away under "More for Jarvis") what it needs, the rules behind its
// decisions, what has gone wrong before and the standard to hit. Native <dialog> at a fixed size; the steps scroll inside
// it. Nothing is saved until Save, and while Jarvis is saving the whole
// box is blocked with a labelled spinner.

interface Props {
  /** The playbook being edited, or a blank one. */
  start: PlaybookDraft
  options: PlaybookOptions
  busy: boolean
  /** Why the last Save didn't take, if it didn't. */
  error: string | null
  onSave: (draft: PlaybookDraft) => void
  /** Only for a playbook that already exists. */
  onDelete?: () => void
  onClose: () => void
}

/** The editor. Mount it to open it; unmount it to close it. */
export function PlaybookEditor({ start, options, busy, error, onSave, onDelete, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  const [draft, setDraft] = useState<PlaybookDraft>(start)
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
  function setStep(index: number, step: PlaybookStep) {
    setDraft((d) => ({ ...d, steps: d.steps.map((a, i) => (i === index ? step : a)) }))
  }

  /** Moves a step one place up (-1) or down (+1). */
  function moveStep(index: number, by: -1 | 1) {
    setDraft((d) => {
      const to = index + by
      if (to < 0 || to >= d.steps.length) return d
      const steps = [...d.steps]
      const [moved] = steps.splice(index, 1)
      steps.splice(to, 0, moved)
      return { ...d, steps }
    })
  }

  /** Checks the playbook and hands it up, or says what's missing. */
  function save() {
    const missing = playbookProblem(draft)
    setProblem(missing)
    if (missing === null) onSave({ ...draft, name: draft.name.trim() })
  }

  return (
    <dialog
      ref={ref}
      className="dialog dialog--detail dialog--playbook glass"
      tabIndex={-1}
      aria-labelledby="playbook-title"
      aria-busy={busy}
      // Esc fires "cancel"; ignored while Jarvis is saving.
      onCancel={(e) => { e.preventDefault(); if (!busy) onClose() }}
    >
      <header className="detail__head">
        <h2 id="playbook-title" className="dialog__title">{start.id ? 'Edit playbook' : 'New playbook'}</h2>
      </header>
      <div className="detail__body playbook__form">
        <label className="field">
          <span className="field__label">Name</span>
          <input className="field__box" value={draft.name} maxLength={60} placeholder="Bedtime" autoComplete="off" onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
        </label>

        <label className="field">
          <span className="field__label">What it’s for</span>
          <input className="field__box" value={draft.purpose} maxLength={200} placeholder="Shut the place down for the night" autoComplete="off" onChange={(e) => setDraft({ ...draft, purpose: e.target.value })} />
        </label>

        <label className="field">
          <span className="field__label">When</span>
          <select className="field__box" value={draft.trigger.type} onChange={(e) => setDraft({ ...draft, trigger: blankTrigger(e.target.value as PlaybookTrigger['type']) })}>
            {TRIGGER_CHOICES.map((c) => <option key={c.type} value={c.type}>{c.label}</option>)}
          </select>
        </label>
        <TriggerFields trigger={draft.trigger} onChange={(trigger) => setDraft({ ...draft, trigger })} />

        <h3 className="playbook__heading">Then</h3>
        {draft.steps.length === 0 ? <p className="playbook__hint">No steps yet. Add the first one below.</p> : null}
        <ol className="playbook__steps">
          {draft.steps.map((step, i) => (
            <li key={i} className="playbook__step" aria-label={`Step ${i + 1}`}>
              <div className="playbook__stephead">
                <span className="playbook__num">{i + 1}</span>
                <span className="playbook__kind">{STEP_CHOICES.find((c) => c.type === step.type)?.label}</span>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Move step ${i + 1} up`} disabled={i === 0} onClick={() => moveStep(i, -1)}>↑</button>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Move step ${i + 1} down`} disabled={i === draft.steps.length - 1} onClick={() => moveStep(i, 1)}>↓</button>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Remove step ${i + 1}`} onClick={() => setDraft({ ...draft, steps: draft.steps.filter((_, j) => j !== i) })}>✕</button>
              </div>
              <StepFields step={step} options={options} onChange={(next) => setStep(i, next)} />
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
              const type = e.target.value as PlaybookStep['type']
              if (type) setDraft({ ...draft, steps: [...draft.steps, blankStep(type, options)] })
            }}
          >
            <option value="">Choose what happens…</option>
            {STEP_CHOICES.map((c) => <option key={c.type} value={c.type}>{c.label}</option>)}
          </select>
        </label>
        <h3 className="playbook__heading">Done when</h3>
        <p className="playbook__hint">Jarvis checks each of these after every run, and tells you if one didn’t hold.</p>
        <LineList label="Done item" placeholder="Every light is off" add="Add a check" lines={draft.done} onChange={(done) => setDraft({ ...draft, done })} />

        <details className="playbook__more">
          <summary>More for Jarvis</summary>
          <label className="field">
            <span className="field__label">When he should use it without being told</span>
            <textarea className="field__box field__box--tall" value={draft.whenToUse} maxLength={500} placeholder="When I ask what my week looks like" onChange={(e) => setDraft({ ...draft, whenToUse: e.target.value })} />
          </label>
          <h3 className="playbook__heading">What it needs</h3>
          <PairList label="Input" first="What" second="Where it lives" add="Add an input" rows={draft.inputs.map((r) => [r.name, r.where])} onChange={(rows) => setDraft({ ...draft, inputs: rows.map(([name, where]) => ({ name, where })) })} />
          <h3 className="playbook__heading">Decisions</h3>
          <PairList label="Decision" first="If…" second="Then…" add="Add a decision" rows={draft.decisions.map((r) => [r.if, r.then])} onChange={(rows) => setDraft({ ...draft, decisions: rows.map(([when, then]) => ({ if: when, then })) })} />
          <h3 className="playbook__heading">Things that have gone wrong</h3>
          <LineList label="Edge case" placeholder="An all-day event hides a timed one" add="Add one" lines={draft.edgeCases} onChange={(edgeCases) => setDraft({ ...draft, edgeCases })} />
          <label className="field">
            <span className="field__label">The standard to hit</span>
            <textarea className="field__box field__box--tall" value={draft.standard} maxLength={500} placeholder="Short enough to read in a minute" onChange={(e) => setDraft({ ...draft, standard: e.target.value })} />
          </label>
          <label className="field">
            <span className="field__label">What a bad version looks like</span>
            <textarea className="field__box field__box--tall" value={draft.badVersion} maxLength={500} placeholder="A list of everything with no judgment about what matters" onChange={(e) => setDraft({ ...draft, badVersion: e.target.value })} />
          </label>
        </details>
        {problem || error ? <p className="dialog__error" role="alert">{problem ?? error}</p> : null}
      </div>
      <div className="dialog__actions">
        {onDelete ? <button type="button" className="btn btn--quiet playbook__delete" onClick={onDelete} disabled={busy}>Delete</button> : null}
        <button type="button" className="btn btn--quiet" onClick={onClose} disabled={busy}>Close</button>
        <button type="button" className="btn btn--primary" onClick={save} disabled={busy}>Save</button>
      </div>
      {busy ? <div className="dialog__block"><Spinner label="Saving…" /></div> : null}
    </dialog>
  )
}

/** The extra boxes a trigger needs: a time and days, or how long away counts. */
function TriggerFields({ trigger, onChange }: { trigger: PlaybookTrigger; onChange: (t: PlaybookTrigger) => void }) {
  if (trigger.type === 'time') {
    /** Adds or removes one day. */
    const toggleDay = (day: PlaybookDay) => {
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
          <span className="field__label" id="playbook-days">Days</span>
          <div className="playbook__days" role="group" aria-labelledby="playbook-days">
            {DAYS.map((d) => (
              <button key={d.id} type="button" className="segmented__opt" aria-pressed={trigger.days.includes(d.id)} onClick={() => toggleDay(d.id)}>{d.label}</button>
            ))}
          </div>
          <span className="playbook__hint">None picked means every day.</span>
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
  if (trigger.type === 'asleep') return <p className="playbook__hint">Runs when night mode turns on, from the Apple TV’s Night button or your Sleep Focus.</p>
  if (trigger.type === 'awake') return <p className="playbook__hint">Runs when you’re marked awake: leaving night mode, or the first time you talk to Jarvis.</p>
  return null
}

/** The boxes one step needs, by its kind. */
function StepFields({ step, options, onChange }: { step: PlaybookStep; options: PlaybookOptions; onChange: (a: PlaybookStep) => void }) {
  if (step.type === 'device') {
    const device = options.devices.find((d) => d.entity === step.entity)
    const commands = device?.commands ?? [step.command]
    return (
      <div className="playbook__fields">
        <select className="field__box" aria-label="Device" value={step.entity} onChange={(e) => {
          const next = options.devices.find((d) => d.entity === e.target.value)
          onChange({ type: 'device', entity: e.target.value, command: next?.commands[0] ?? 'turn_off' })
        }}>
          {device ? null : <option value={step.entity}>{step.entity || 'Pick a device'}</option>}
          {options.devices.map((d) => <option key={d.entity} value={d.entity}>{d.name}</option>)}
        </select>
        <select className="field__box" aria-label="What to do" value={step.command} onChange={(e) => onChange({ type: 'device', entity: step.entity, command: e.target.value })}>
          {commands.map((c) => <option key={c} value={c}>{commandLabel(c)}</option>)}
        </select>
        {commandTakesValue(step.command) ? (
          <input className="field__box" aria-label="Value" value={step.value ?? ''} placeholder={valueHint(step.command)} onChange={(e) => onChange({ ...step, value: valueOf(step.command, e.target.value) })} />
        ) : null}
      </div>
    )
  }
  if (step.type === 'scene') {
    return (
      <select className="field__box" aria-label="Scene" value={step.entity} onChange={(e) => onChange({ type: 'scene', entity: e.target.value })}>
        {options.scenes.some((s) => s.entity === step.entity) ? null : <option value={step.entity}>{step.entity || 'Pick a scene'}</option>}
        {options.scenes.map((s) => <option key={s.entity} value={s.entity}>{s.name}</option>)}
      </select>
    )
  }
  if (step.type === 'app') {
    const screen = options.apps.find((a) => a.entity === step.entity)
    const apps = screen?.apps ?? [step.app]
    return (
      <div className="playbook__fields">
        <select className="field__box" aria-label="TV" value={step.entity} onChange={(e) => {
          const next = options.apps.find((a) => a.entity === e.target.value)
          onChange({ type: 'app', entity: e.target.value, app: next?.apps[0] ?? '' })
        }}>
          {screen ? null : <option value={step.entity}>{step.entity || 'Pick a TV'}</option>}
          {options.apps.map((a) => <option key={a.entity} value={a.entity}>{a.name}</option>)}
        </select>
        <select className="field__box" aria-label="App" value={step.app} onChange={(e) => onChange({ ...step, app: e.target.value })}>
          {apps.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
      </div>
    )
  }
  if (step.type === 'notify') {
    return <input className="field__box" aria-label="Notification text" value={step.text} maxLength={300} placeholder="Time to head out" onChange={(e) => onChange({ ...step, text: e.target.value })} />
  }
  if (step.type === 'think') {
    return (
      <>
        <textarea className="field__box field__box--tall" aria-label="What Jarvis should do" value={step.text} maxLength={2000} placeholder="Tell me tomorrow’s first meeting and the weather" onChange={(e) => onChange({ ...step, text: e.target.value })} />
        <select className="field__box" aria-label="Who does it" value={step.model} onChange={(e) => onChange({ ...step, model: e.target.value as PlaybookThinker })}>
          {THINKER_CHOICES.map((c) => <option key={c.model} value={c.model}>{c.label}</option>)}
        </select>
      </>
    )
  }
  if (step.type === 'email') {
    return (
      <>
        <input className="field__box" type="text" inputMode="email" aria-label="To" value={step.to} placeholder="someone@example.com, another@example.com" autoComplete="off" onChange={(e) => onChange({ ...step, to: e.target.value })} />
        <input className="field__box" aria-label="Subject" value={step.subject} maxLength={200} placeholder="Subject" onChange={(e) => onChange({ ...step, subject: e.target.value })} />
        <textarea className="field__box field__box--tall" aria-label="Message" value={step.body} maxLength={5000} placeholder="Message" onChange={(e) => onChange({ ...step, body: e.target.value })} />
        <ConfirmSwitch on={step.confirm} onChange={(confirm) => onChange({ ...step, confirm })} />
      </>
    )
  }
  return (
    <label className="playbook__fields playbook__fields--inline">
      <input className="field__box" type="number" min={1} max={600} inputMode="numeric" aria-label="Seconds to wait" value={step.seconds} onChange={(e) => onChange({ type: 'wait', seconds: Number(e.target.value) || 0 })} />
      <span className="playbook__hint">seconds</span>
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
    <button type="button" role="switch" aria-checked={on} className="switch playbook__confirm" onClick={() => onChange(!on)}>
      <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
      <span>Ask me first, each time</span>
    </button>
  )
}

/** A list of one-line items (done checks, edge cases) with a box each, ✕ to drop one and a button to add one. */
function LineList({ label, placeholder, add, lines, onChange }: { label: string; placeholder: string; add: string; lines: string[]; onChange: (lines: string[]) => void }) {
  return (
    <div className="playbook__list">
      {lines.map((line, i) => (
        <div key={i} className="playbook__line">
          <input className="field__box" aria-label={`${label} ${i + 1}`} value={line} maxLength={300} placeholder={placeholder} onChange={(e) => onChange(lines.map((l, j) => (j === i ? e.target.value : l)))} />
          <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Remove ${label.toLowerCase()} ${i + 1}`} onClick={() => onChange(lines.filter((_, j) => j !== i))}>✕</button>
        </div>
      ))}
      {lines.length < 10 ? <button type="button" className="btn btn--quiet playbook__add" onClick={() => onChange([...lines, ''])}>{add}</button> : null}
    </div>
  )
}

/** A list of two-box rows (an input and where it lives; an if and its then), with ✕ and an add button. */
function PairList({ label, first, second, add, rows, onChange }: { label: string; first: string; second: string; add: string; rows: [string, string][]; onChange: (rows: [string, string][]) => void }) {
  /** Replaces one box of one row. */
  function setCell(index: number, cell: 0 | 1, value: string) {
    onChange(rows.map((row, i) => {
      if (i !== index) return row
      if (cell === 0) return [value, row[1]]
      return [row[0], value]
    }))
  }
  return (
    <div className="playbook__list">
      {rows.map((row, i) => (
        <div key={i} className="playbook__line playbook__line--pair">
          <input className="field__box" aria-label={`${label} ${i + 1}: ${first}`} value={row[0]} maxLength={200} placeholder={first} onChange={(e) => setCell(i, 0, e.target.value)} />
          <input className="field__box" aria-label={`${label} ${i + 1}: ${second}`} value={row[1]} maxLength={300} placeholder={second} onChange={(e) => setCell(i, 1, e.target.value)} />
          <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Remove ${label.toLowerCase()} ${i + 1}`} onClick={() => onChange(rows.filter((_, j) => j !== i))}>✕</button>
        </div>
      ))}
      {rows.length < 10 ? <button type="button" className="btn btn--quiet playbook__add" onClick={() => onChange([...rows, ['', '']])}>{add}</button> : null}
    </div>
  )
}
