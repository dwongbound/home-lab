import { useEffect, useRef, useState } from 'react'
import { draftPlaybook } from '../api/client'
import { AUTO, DAYS, TRIGGER_CHOICES, activeField, blankStep, blankTrigger, choicesFor, playbookProblem, stepChoices, stepLabel, stepTypeOf, withField } from '../lib/playbooks'
import type { PlaybookDay, PlaybookDraft, PlaybookOptions, PlaybookStep, PlaybookTrigger, StepFieldRule, StepValue } from '../types'
import { useScrollLock } from '../useScrollLock'
import { Spinner } from './Spinner'

// The pop-up where a playbook is written. It reads top to bottom as three
// plain questions (Dylan, 2026-11-19: the first one was too hard to follow):
// 1 when does it run, 2 what happens, 3 how Jarvis knows it worked. A new
// playbook starts with a "Describe it" box: a sentence or two, and Jarvis
// fills the whole form in to look over (nothing is saved until Save). Steps
// are added from a row of buttons. Folded away under "More for Jarvis" are what it needs, the rules behind its
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
  const [wish, setWish] = useState('')
  const [drafting, setDrafting] = useState(false)
  const [draftNote, setDraftNote] = useState<string | null>(null)
  const [assumed, setAssumed] = useState<string[]>([])
  useScrollLock()
  // Jarvis writing a draft blocks the box just as saving does.
  const blocked = busy || drafting

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

  /** Has Jarvis fill the form in from the description. */
  async function writeDraft() {
    if (wish.trim() === '') {
      setDraftNote('Say what it should do first')
      return
    }
    setDrafting(true)
    setDraftNote(null)
    const result = await draftPlaybook(wish.trim())
    setDrafting(false)
    if (!result.ok) {
      setDraftNote(result.message)
      return
    }
    setDraft(result.playbook)
    setProblem(null)
    setDraftNote('Jarvis filled it in below. Check it over, change anything, then Save.')
    // What he assumed (a lamp that isn't listed, say) is said up front, not left folded away.
    setAssumed(result.playbook.edgeCases)
  }

  /** Checks the playbook and hands it up, or says what's missing. */
  function save() {
    const missing = playbookProblem(draft, options)
    setProblem(missing)
    if (missing === null) onSave({ ...draft, name: draft.name.trim() })
  }

  return (
    <dialog
      ref={ref}
      className="dialog dialog--detail dialog--playbook glass"
      tabIndex={-1}
      aria-labelledby="playbook-title"
      aria-busy={blocked}
      // Esc fires "cancel"; ignored while Jarvis is saving or writing.
      onCancel={(e) => { e.preventDefault(); if (!blocked) onClose() }}
    >
      <header className="detail__head">
        <h2 id="playbook-title" className="dialog__title">{start.id ? 'Edit playbook' : 'New playbook'}</h2>
      </header>
      <div className="detail__body playbook__form">
        {start.id ? null : (
          <div className="playbook__describe">
            <label className="field">
              <span className="field__label">Describe it, and Jarvis fills in the rest</span>
              <textarea className="field__box field__box--tall" value={wish} maxLength={1000} placeholder="At 11 on weeknights, turn off the lights and tell me tomorrow’s first meeting" onChange={(e) => setWish(e.target.value)} />
            </label>
            <button type="button" className="btn btn--primary playbook__add" onClick={() => void writeDraft()} disabled={blocked}>Write it for me</button>
            {draftNote ? <p className="playbook__hint" role="status">{draftNote}</p> : <p className="playbook__hint">Or fill it in yourself below.</p>}
            {assumed.length > 0 ? (
              <ul className="playbook__assumed" aria-label="What Jarvis assumed">
                {assumed.map((line) => <li key={line}>{line}</li>)}
              </ul>
            ) : null}
          </div>
        )}
        <label className="field">
          <span className="field__label">Name</span>
          <input className="field__box" value={draft.name} maxLength={60} placeholder="Bedtime" autoComplete="off" onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
        </label>

        <label className="field">
          <span className="field__label">What it’s for</span>
          <input className="field__box" value={draft.purpose} maxLength={200} placeholder="Shut the place down for the night" autoComplete="off" onChange={(e) => setDraft({ ...draft, purpose: e.target.value })} />
        </label>

        <h3 className="playbook__heading"><span className="playbook__num">1</span>When does it run?</h3>
        <label className="field">
          <span className="field__label">Start it</span>
          <select className="field__box" value={draft.trigger.type} onChange={(e) => setDraft({ ...draft, trigger: blankTrigger(e.target.value as PlaybookTrigger['type']) })}>
            {TRIGGER_CHOICES.map((c) => <option key={c.type} value={c.type}>{c.label}</option>)}
          </select>
        </label>
        <TriggerFields trigger={draft.trigger} onChange={(trigger) => setDraft({ ...draft, trigger })} />

        <h3 className="playbook__heading"><span className="playbook__num">2</span>What happens?</h3>
        {draft.steps.length === 0 ? <p className="playbook__hint">Nothing yet. Tap a button below to add the first step; they run top to bottom.</p> : null}
        <ol className="playbook__steps">
          {draft.steps.map((step, i) => (
            <li key={i} className="playbook__step" aria-label={`Step ${i + 1}`}>
              <div className="playbook__stephead">
                <span className="playbook__num">{i + 1}</span>
                <span className="playbook__kind">{stepLabel(step, options)}</span>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Move step ${i + 1} up`} disabled={i === 0} onClick={() => moveStep(i, -1)}>↑</button>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Move step ${i + 1} down`} disabled={i === draft.steps.length - 1} onClick={() => moveStep(i, 1)}>↓</button>
                <button type="button" className="btn btn--quiet playbook__mini" aria-label={`Remove step ${i + 1}`} onClick={() => setDraft({ ...draft, steps: draft.steps.filter((_, j) => j !== i) })}>✕</button>
              </div>
              <StepFields step={step} options={options} onChange={(next) => setStep(i, next)} />
            </li>
          ))}
        </ol>
        <div className="field">
          <span className="field__label" id="playbook-add">Add a step</span>
          {/* One tap adds that kind of step at the end. */}
          <div className="playbook__chips" role="group" aria-labelledby="playbook-add">
            {stepChoices(options).map((c) => (
              <button key={c.type} type="button" className="segmented__opt" title={c.label} onClick={() => setDraft({ ...draft, steps: [...draft.steps, blankStep(c.type, options)] })}>{c.short}</button>
            ))}
          </div>
        </div>
        <h3 className="playbook__heading"><span className="playbook__num">3</span>How does Jarvis know it worked? <span className="playbook__optional">Optional</span></h3>
        <p className="playbook__hint">He checks each of these after every run, and tells you if one didn’t hold.</p>
        <LineList label="Done item" placeholder="Every light is off" add="Add a check" lines={draft.done} onChange={(done) => setDraft({ ...draft, done })} />

        <details className="playbook__more">
          <summary>More for Jarvis <span className="playbook__optional">Optional, for jobs that need judgment</span></summary>
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
        {onDelete ? <button type="button" className="btn btn--quiet playbook__delete" onClick={onDelete} disabled={blocked}>Delete</button> : null}
        <button type="button" className="btn btn--quiet" onClick={onClose} disabled={blocked}>Close</button>
        <button type="button" className="btn btn--primary" onClick={save} disabled={blocked}>Save</button>
      </div>
      {busy ? <div className="dialog__block"><Spinner label="Saving…" /></div> : null}
      {drafting ? <div className="dialog__block"><Spinner label="Jarvis is writing it…" /></div> : null}
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

/** The boxes one step needs, drawn from Jarvis's description of its kind. */
function StepFields({ step, options, onChange }: { step: PlaybookStep; options: PlaybookOptions; onChange: (a: PlaybookStep) => void }) {
  const described = stepTypeOf(step, options)
  if (!described) return <p className="playbook__hint">Jarvis runs this step as it is. There’s nothing to fill in here.</p>
  const boxes = []
  for (const field of described.fields) {
    const rule = activeField(field, step, options)
    if (rule === null) continue
    boxes.push(
      <FieldBox key={field.key} rule={rule} value={step[field.key]} choices={rule.kind === 'choice' ? choicesFor(rule, step, options) : []} onChange={(value) => onChange(withField(step, field.key, value, options))} />,
    )
  }
  return <div className="playbook__fields">{boxes}</div>
}

/** A typed number, or nothing when the box is empty or isn't a number yet. */
function typedNumber(typed: string): number | undefined {
  if (typed.trim() === '') return undefined
  const number = Number(typed)
  return Number.isFinite(number) ? number : undefined
}

/** One box of a step: a dropdown, a switch, a number or words, by the field's kind. */
function FieldBox({ rule, value, choices, onChange }: { rule: StepFieldRule; value: StepValue | undefined; choices: { id: string; name: string }[]; onChange: (value: StepValue | undefined) => void }) {
  const words = typeof value === 'string' ? value : ''
  if (rule.kind === 'bool') {
    return (
      <button type="button" role="switch" aria-checked={value === true} className="switch playbook__confirm playbook__wide" onClick={() => onChange(value !== true)}>
        <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
        <span>{rule.label}</span>
      </button>
    )
  }
  // A pick with nothing listed to pick from (a TV that names no apps) takes typed words.
  if (rule.kind === 'choice' && (choices.length > 0 || !rule.required || !rule.dependsOn)) {
    const listed = choices.some((c) => c.id === words)
    return (
      <select className="field__box" aria-label={rule.label} value={words} onChange={(e) => onChange(e.target.value)}>
        {rule.required ? null : <option value={AUTO}>Jarvis picks</option>}
        {listed || words === AUTO ? null : <option value={words}>{words || `Pick: ${rule.label}`}</option>}
        {choices.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
      </select>
    )
  }
  if (rule.kind === 'number') {
    // The label sits beside the box, since a number alone doesn't say what it counts.
    return (
      <label className="playbook__number playbook__wide">
        <input className="field__box" type="number" min={rule.min} max={rule.max} step={rule.step} inputMode="decimal" aria-label={rule.label} value={typeof value === 'number' ? value : ''} onChange={(e) => onChange(typedNumber(e.target.value))} />
        <span className="playbook__hint">{rule.label}</span>
      </label>
    )
  }
  if (rule.kind === 'longtext') {
    return <textarea className="field__box field__box--tall playbook__wide" aria-label={rule.label} value={words} maxLength={rule.max} placeholder={rule.placeholder ?? rule.label} onChange={(e) => onChange(e.target.value)} />
  }
  if (rule.kind === 'emails') {
    return <input className="field__box playbook__wide" type="text" inputMode="email" aria-label={rule.label} value={words} placeholder="someone@example.com, another@example.com" autoComplete="off" onChange={(e) => onChange(e.target.value)} />
  }
  return <input className="field__box playbook__wide" aria-label={rule.label} value={words} maxLength={rule.max} placeholder={rule.placeholder ?? rule.label} onChange={(e) => onChange(e.target.value)} />
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
