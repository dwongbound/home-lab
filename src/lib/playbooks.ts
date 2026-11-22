import type { Playbook, PlaybookDay, PlaybookDraft, PlaybookOptions, PlaybookStep, PlaybookTrigger, StepField, StepFieldRule, StepType, StepValue } from '../types'

// Words and starting values for the Playbooks page: how a trigger and a
// step read in a sentence, what a new playbook or step starts as, and what's
// still missing before one can be saved. The kinds of step and their fields
// come from Jarvis (`options.stepTypes`), so nothing here names a kind. The
// server checks again (server/sources/playbooks.mjs); this copy is so the
// page can say what's wrong before anything is sent.

export const DAYS: { id: PlaybookDay; label: string }[] = [
  { id: 'mon', label: 'Mon' },
  { id: 'tue', label: 'Tue' },
  { id: 'wed', label: 'Wed' },
  { id: 'thu', label: 'Thu' },
  { id: 'fri', label: 'Fri' },
  { id: 'sat', label: 'Sat' },
  { id: 'sun', label: 'Sun' },
]

export const TRIGGER_CHOICES: { type: PlaybookTrigger['type']; label: string }[] = [
  { type: 'time', label: 'At a time' },
  { type: 'arrive', label: 'When I get home' },
  { type: 'leave', label: 'When I leave home' },
  { type: 'asleep', label: 'When I go to sleep' },
  { type: 'awake', label: 'When I wake up' },
  { type: 'manual', label: 'When I ask, or the job comes up' },
]

// The page's word for a pick left to Jarvis (who does a thinking step).
export const AUTO = 'auto'

/** "08:30" as "8:30 AM". */
export function clockLabel(at: string): string {
  const [h, m] = at.split(':').map(Number)
  if (!Number.isFinite(h) || !Number.isFinite(m)) return at
  const hour = h % 12 === 0 ? 12 : h % 12
  return `${hour}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`
}

/** Which days a timed playbook runs, in words: "every day", "weekdays", "Mon, Wed". */
export function daysLabel(days: PlaybookDay[]): string {
  if (days.length === 0 || days.length === 7) return 'every day'
  const has = (d: PlaybookDay) => days.includes(d)
  const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri'] as PlaybookDay[]
  if (days.length === 5 && weekdays.every(has)) return 'weekdays'
  if (days.length === 2 && has('sat') && has('sun')) return 'weekends'
  return DAYS.filter((d) => has(d.id)).map((d) => d.label).join(', ')
}

/** When a playbook runs, as one line. */
export function triggerLine(trigger: PlaybookTrigger): string {
  if (trigger.type === 'time') return `At ${clockLabel(trigger.at)}, ${daysLabel(trigger.days)}`
  if (trigger.type === 'arrive') {
    if (trigger.minAway > 0) return `When I get home after ${trigger.minAway} min away`
    return 'When I get home'
  }
  if (trigger.type === 'leave') return 'When I leave home'
  if (trigger.type === 'asleep') return 'When I go to sleep'
  if (trigger.type === 'awake') return 'When I wake up'
  return 'When I ask, or the job comes up'
}

/** One thing a field can be set to: the value that's saved and the words shown for it. */
export interface StepChoice { id: string; name: string }

/** An id in plain words: "turn_off" reads "Turn off". */
function plainWords(id: string): string {
  const words = id.replace(/_/g, ' ')
  return words.charAt(0).toUpperCase() + words.slice(1)
}

/** Every address in a "to" box: one, or several split by commas. */
export function emailAddresses(to: string): string[] {
  return to.split(',').map((a) => a.trim()).filter((a) => a !== '')
}

/** A short piece of typed text for a one-line summary. */
function clip(words: string, max = 48): string {
  if (words.length <= max) return words
  return `${words.slice(0, max - 1).trimEnd()}…`
}

/** Jarvis's description of a step's kind; undefined for a kind he didn't describe. */
export function stepTypeOf(step: PlaybookStep, options: PlaybookOptions): StepType | undefined {
  return options.stepTypes.find((t) => t.type === step.type)
}

/** What heads a step in the editor: its kind's label, or the bare kind when Jarvis didn't describe it. */
export function stepLabel(step: PlaybookStep, options: PlaybookOptions): string {
  return stepTypeOf(step, options)?.label ?? plainWords(step.type)
}

/** One of the options lists by name (devices, scenes, apps, jobs, thinkers), as rows with an id. */
function optionRows(name: string, options: PlaybookOptions): { id: string; name: string; row: Record<string, unknown> }[] {
  const list = (options as unknown as Record<string, unknown>)[name]
  if (!Array.isArray(list)) return []
  const rows = []
  for (const row of list as Record<string, unknown>[]) {
    // Devices, scenes and TVs go by `entity`; jobs and thinkers by `id`.
    const id = typeof row?.entity === 'string' ? row.entity : row?.id
    if (typeof id === 'string') rows.push({ id, name: typeof row.name === 'string' ? row.name : id, row })
  }
  return rows
}

/** What a choice field offers for this step: fixed words, a whole options list, or the picked row's sub-list. */
export function choicesFor(rule: StepFieldRule, step: PlaybookStep, options: PlaybookOptions): StepChoice[] {
  if (rule.choices) return rule.choices.map((id) => ({ id, name: plainWords(id) }))
  if (!rule.choicesFrom) return []
  const rows = optionRows(rule.choicesFrom, options)
  if (!rule.dependsOn || !rule.choicesKey) return rows.map(({ id, name }) => ({ id, name }))
  // The picked device's commands, the picked TV's apps.
  const picked = rows.find((r) => r.id === step[rule.dependsOn as string])
  const sub = picked?.row[rule.choicesKey]
  if (!Array.isArray(sub)) return []
  return sub.filter((v): v is string => typeof v === 'string').map((id) => ({ id, name: plainWords(id) }))
}

/** The kind of device a step is about (light, climate), for values only some kinds take. */
function deviceKind(step: PlaybookStep, options: PlaybookOptions): string {
  const device = options.devices.find((d) => d.entity === step.entity)
  return device?.kind ?? ''
}

/**
 * The field as it applies to this step right now. A `by_command` field
 * becomes the rule for the picked command, or null when that command takes
 * no value (or takes one only for another kind of device).
 */
export function activeField(field: StepField, step: PlaybookStep, options: PlaybookOptions): (StepFieldRule & { key: string }) | null {
  if (field.kind !== 'by_command') return field
  const picked = step[field.dependsOn ?? '']
  const rule = typeof picked === 'string' ? field.byCommand?.[picked] : undefined
  if (!rule) return null
  if (rule.onlyDomains && !rule.onlyDomains.includes(deviceKind(step, options))) return null
  return { key: field.key, ...rule }
}

/** A step's value as it reads in the row: a pick's name, or the typed words cut short. */
function valueWords(step: PlaybookStep, key: string, byName: boolean, options: PlaybookOptions): string {
  const value = step[key]
  if (value === undefined || value === '' || value === AUTO) return ''
  const field = stepTypeOf(step, options)?.fields.find((f) => f.key === key)
  const rule = field ? activeField(field, step, options) : null
  if (rule?.kind === 'choice' && typeof value === 'string') {
    const name = choicesFor(rule, step, options).find((c) => c.id === value)?.name
    // "{entity.name}" asks for the name as given; a bare "{command}" reads mid-sentence.
    if (byName) return name ?? value
    return value.replace(/_/g, ' ')
  }
  return clip(String(value))
}

/** One step, as one line, from its kind's summary pattern ("{entity.name}: {command} {value}"). */
export function stepLine(step: PlaybookStep, options: PlaybookOptions): string {
  const described = stepTypeOf(step, options)
  if (!described) return plainWords(step.type)
  const line = described.summary.replace(/\{([a-z0-9_]+)(\.name)?\}/g, (_all, key: string, byName?: string) => valueWords(step, key, byName !== undefined, options))
  return line.replace(/\s+/g, ' ').trim()
}

/** The kinds of step the editor can add: all Jarvis describes, but not one whose only pick has nothing to pick from. */
export function stepChoices(options: PlaybookOptions): StepType[] {
  return options.stepTypes.filter((t) => {
    const empty = t.fields.find((f) => f.kind === 'choice' && f.required && !f.dependsOn && choicesFor(f, { type: t.type }, options).length === 0)
    return empty === undefined
  })
}

/** What a field starts as, given the step so far; undefined = left out. */
function startValue(rule: StepFieldRule, step: PlaybookStep, options: PlaybookOptions): StepValue | undefined {
  if (rule.kind === 'choice') {
    // A pick that isn't required is left to Jarvis.
    if (!rule.required) return AUTO
    return choicesFor(rule, step, options)[0]?.id ?? ''
  }
  if (rule.kind === 'bool') return rule.default === true
  if (rule.kind === 'number') {
    // No default = an empty box to fill in.
    return typeof rule.default === 'number' ? rule.default : undefined
  }
  return ''
}

/** What a step of one kind starts as: the first device, scene or app Jarvis lists, and his defaults. */
export function blankStep(type: string, options: PlaybookOptions): PlaybookStep {
  const step: PlaybookStep = { type }
  const fields = options.stepTypes.find((t) => t.type === type)?.fields ?? []
  for (const field of fields) {
    const rule = activeField(field, step, options)
    if (rule) step[field.key] = startValue(rule, step, options)
  }
  return step
}

/** Whether a field hangs off another one, directly or through the command it depends on. */
function hangsOff(field: StepField, key: string): boolean {
  if (field.dependsOn === key) return true
  return Object.values(field.byCommand ?? {}).some((rule) => rule.dependsOn === key)
}

/**
 * A step with one value changed. Fields that hang off it start over, since
 * another device has other commands and another command takes another value.
 */
export function withField(step: PlaybookStep, key: string, value: StepValue | undefined, options: PlaybookOptions): PlaybookStep {
  const next: PlaybookStep = { ...step, [key]: value }
  const fields = stepTypeOf(step, options)?.fields ?? []
  const changed = [key]
  for (const field of fields) {
    if (!changed.some((c) => hangsOff(field, c))) continue
    const rule = activeField(field, next, options)
    next[field.key] = rule ? startValue(rule, next, options) : undefined
    changed.push(field.key)
  }
  return next
}

/** What one field still needs, or null when it's fine. */
function fieldProblem(rule: StepFieldRule, value: StepValue | undefined): string | null {
  if (rule.kind === 'bool') return null
  if (rule.kind === 'emails') {
    const addresses = emailAddresses(typeof value === 'string' ? value : '')
    const most = rule.maxItems ?? 10
    if (addresses.length === 0) return rule.required ? `give it one to ${most} email addresses` : null
    if (addresses.length > most) return `give it one to ${most} email addresses`
    if (!addresses.every((a) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(a))) return 'check the email address'
    return null
  }
  const empty = value === undefined || value === '' || (typeof value === 'string' && value.trim() === '')
  if (empty) return rule.required ? `${rule.label} is missing` : null
  if (rule.kind === 'number') {
    const low = rule.min ?? -Infinity
    const high = rule.max ?? Infinity
    if (typeof value !== 'number' || value < low || value > high) return `${rule.label} must be between ${low} and ${high}`
  }
  return null
}

/** What one step is still missing, or null when it's complete. A kind Jarvis didn't describe is his to judge. */
function stepProblem(step: PlaybookStep, options: PlaybookOptions): string | null {
  const fields = stepTypeOf(step, options)?.fields ?? []
  for (const field of fields) {
    const rule = activeField(field, step, options)
    const problem = rule ? fieldProblem(rule, step[field.key]) : null
    if (problem) return problem
  }
  return null
}

/** A new, empty playbook: runs only when asked until a trigger is picked. */
export function blankPlaybook(): PlaybookDraft {
  return {
    name: '',
    enabled: true,
    purpose: '',
    whenToUse: '',
    trigger: { type: 'manual' },
    inputs: [],
    steps: [],
    decisions: [],
    done: [],
    edgeCases: [],
    standard: '',
    badVersion: '',
  }
}

/** What a trigger of one type starts as when it's picked. */
export function blankTrigger(type: PlaybookTrigger['type']): PlaybookTrigger {
  if (type === 'time') return { type, at: '08:00', days: [] }
  if (type === 'arrive') return { type, zone: 'home', minAway: 15 }
  if (type === 'leave') return { type, zone: 'home' }
  return { type }
}

/** Why a playbook can't be saved yet, in plain words; null when it can. */
export function playbookProblem(draft: PlaybookDraft, options: PlaybookOptions): string | null {
  if (!draft.name.trim()) return 'Give the playbook a name'
  if (draft.trigger.type === 'time' && !/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.trigger.at)) return 'Pick a time'
  if (draft.steps.length === 0) return 'Add at least one step'
  for (let i = 0; i < draft.steps.length; i += 1) {
    const problem = stepProblem(draft.steps[i], options)
    if (problem) return `Step ${i + 1}: ${problem}`
  }
  return null
}

/** A saved playbook as the editor starts with it: everything but what Jarvis keeps (id stays, last run and author go). */
export function draftOf(playbook: Playbook): PlaybookDraft {
  const { lastRun: _lastRun, madeBy: _madeBy, ...draft } = playbook
  return draft
}

/**
 * How a playbook's last run went, as the items of its done checklist that
 * didn't hold: "Every light is off: the porch lights were still on".
 */
export function failedChecks(playbook: Playbook): string[] {
  const checks = playbook.lastRun?.checks ?? []
  return checks.filter((c) => !c.ok).map((c) => (c.why ? `${c.item}: ${c.why}` : c.item))
}
