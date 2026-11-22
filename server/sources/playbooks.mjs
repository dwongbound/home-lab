// Playbooks: jobs Jarvis knows how to do (Dylan, 2026-11-18). Each has what
// it's for, when it runs (a set time, arriving or leaving, going to sleep or
// waking, or only when asked), its steps, the rules behind the decisions and
// a done checklist he checks himself against. Jarvis owns and runs them
// (GET/POST /playbooks); this file checks what the page sends before it's
// passed on, and turns Jarvis's snake_case into the page's shape and back.

import { DEFAULT_STEP_TYPES, DEFAULT_THINKERS, parseNamed, parseStepTypes } from './step-types.mjs'

export const PLAYBOOK_DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
const TRIGGER_TYPES = ['time', 'arrive', 'leave', 'asleep', 'awake', 'manual']
// The page's word for a pick left to Jarvis (who does a thinking step).
const AUTO = 'auto'
const STEP_NAME = /^[a-z][a-z0-9_]{0,39}$/
const MAX_KEYS = 16
const MAX_STEPS = 20
const MAX_LINES = 10
const MAX_BODY = 5000
const MAX_TO = 10
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

/** A trimmed string no longer than max, or '' when it isn't a string. */
function text(value, max = 200) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, max)
}

/** A list of non-empty lines (done items, edge cases), trimmed and capped. */
function lines(value, max = 300) {
  if (!Array.isArray(value)) return []
  return value.map((v) => text(v, max)).filter((v) => v !== '').slice(0, MAX_LINES)
}

/** A list of two-part rows ({name, where} or {if, then}), keeping rows with both parts. */
function pairs(value, first, second) {
  if (!Array.isArray(value)) return []
  return value
    .map((row) => ({ [first]: text(row?.[first], 200), [second]: text(row?.[second], 300) }))
    .filter((row) => row[first] !== '' && row[second] !== '')
    .slice(0, MAX_LINES)
}

/** The trigger as the page sent it, cleaned; null when it makes no sense. */
function cleanTrigger(raw) {
  if (!raw || !TRIGGER_TYPES.includes(raw.type)) return null
  if (raw.type === 'time') {
    if (typeof raw.at !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(raw.at)) return null
    const days = Array.isArray(raw.days) ? PLAYBOOK_DAYS.filter((d) => raw.days.includes(d)) : []
    return { type: 'time', at: raw.at, days }
  }
  if (raw.type === 'arrive') {
    const minutes = Number(raw.minAway)
    const minAway = Number.isFinite(minutes) ? Math.min(1440, Math.max(0, Math.round(minutes))) : 15
    return { type: 'arrive', zone: text(raw.zone, 60) || 'home', minAway }
  }
  if (raw.type === 'leave') return { type: 'leave', zone: text(raw.zone, 60) || 'home' }
  return { type: raw.type }
}

/** One value of a step as the page may send it: words, a number, yes/no or a short list of words. */
function stepValue(value) {
  if (typeof value === 'string') return value.trim() === '' ? undefined : text(value, MAX_BODY)
  if (typeof value === 'number') return Number.isFinite(value) ? value : undefined
  if (typeof value === 'boolean') return value
  if (Array.isArray(value)) return strings(value).map((v) => text(v, 200)).filter((v) => v !== '').slice(0, MAX_TO)
  return undefined
}

/** A step's type and its plain values, whatever kind of step it is; null when it has no usable type. */
function plainStep(raw) {
  if (!raw || typeof raw.type !== 'string' || !STEP_NAME.test(raw.type)) return null
  const step = { type: raw.type }
  for (const [key, value] of Object.entries(raw).slice(0, MAX_KEYS)) {
    const cleaned = stepValue(value)
    if (key !== 'type' && STEP_NAME.test(key) && cleaned !== undefined) step[key] = cleaned
  }
  return step
}

/** Every address in a "to" value: a list, or one string split by commas. */
function addresses(value) {
  const list = Array.isArray(value) ? value : String(value ?? '').split(',')
  return list.map((a) => String(a).trim()).filter((a) => a !== '')
}

/**
 * One field's value checked against Jarvis's description of it. Returns
 * {value} (undefined = leave it out) or {bad: true} when it can't be right.
 */
function checkField(field, value) {
  if (field.kind === 'emails') {
    const to = addresses(value)
    if (to.length === 0) return field.required ? { bad: true } : { value: undefined }
    if (to.length > (field.maxItems ?? MAX_TO) || !to.every((a) => EMAIL.test(a))) return { bad: true }
    // The page keeps several addresses as one comma-separated line.
    return { value: to.join(', ') }
  }
  if (field.kind === 'bool') return { value: value === true }
  if (field.kind === 'number') {
    const number = typeof value === 'string' ? Number(value) : value
    if (typeof number !== 'number' || !Number.isFinite(number)) return field.required ? { bad: true } : { value: undefined }
    if (field.min !== undefined && number < field.min) return { bad: true }
    return { value: field.max === undefined ? number : Math.min(field.max, number) }
  }
  if (value === undefined || value === '') return field.required ? { bad: true } : { value: undefined }
  if (typeof value === 'string' && field.max !== undefined) return { value: value.slice(0, field.max) }
  return { value }
}

/**
 * One step, cleaned; null when it's missing what it needs. A kind Jarvis
 * describes is checked field by field; one he doesn't is passed on as it
 * came, for him to judge.
 */
function cleanStep(raw, stepTypes) {
  const step = plainStep(raw)
  if (step === null) return null
  const described = stepTypes.find((t) => t.type === step.type)
  if (!described) return step
  for (const field of described.fields) {
    let rule = field
    if (field.kind === 'by_command') {
      // Which value a command takes; a command with none listed is left as sent.
      rule = field.byCommand?.[step[field.dependsOn]]
      if (!rule) continue
    }
    const checked = checkField(rule, step[field.key])
    if (checked.bad) return null
    if (checked.value === undefined) delete step[field.key]
    else step[field.key] = checked.value
  }
  return step
}

/**
 * A playbook as the page sent it, checked and trimmed. Returns
 * {playbook} when it's fine, or {problem} saying in plain words what's wrong.
 */
export function cleanPlaybook(raw, stepTypes = DEFAULT_STEP_TYPES) {
  const name = text(raw?.name, 60)
  if (!name) return { problem: 'Give the playbook a name' }
  const trigger = cleanTrigger(raw?.trigger)
  if (!trigger) return { problem: 'Pick when the playbook should run' }
  if (!Array.isArray(raw?.steps) || raw.steps.length === 0) return { problem: 'Add at least one step' }
  if (raw.steps.length > MAX_STEPS) return { problem: `A playbook can have up to ${MAX_STEPS} steps` }
  const steps = raw.steps.map((step) => cleanStep(step, stepTypes))
  const bad = steps.findIndex((a) => a === null)
  if (bad >= 0) return { problem: `Step ${bad + 1} is missing something` }
  const playbook = {
    name,
    enabled: raw.enabled !== false,
    purpose: text(raw.purpose, 200),
    whenToUse: text(raw.whenToUse, 500),
    trigger,
    inputs: pairs(raw.inputs, 'name', 'where'),
    steps,
    decisions: pairs(raw.decisions, 'if', 'then'),
    done: lines(raw.done),
    edgeCases: lines(raw.edgeCases),
    standard: text(raw.standard, 500),
    badVersion: text(raw.badVersion, 500),
  }
  const id = text(raw?.id, 80)
  if (id) playbook.id = id
  return { playbook }
}

/** Whether a field is a pick the step may leave to Jarvis ("auto" on the page). */
function leftToJarvis(field) {
  return field.kind === 'choice' && !field.required
}

/** One cleaned step in the words Jarvis uses: addresses as a list, nothing where he's to pick. */
function toJarvisStep(step, stepTypes) {
  const out = { ...step }
  const fields = stepTypes.find((t) => t.type === step.type)?.fields ?? []
  for (const field of fields) {
    if (field.kind === 'emails' && out[field.key] !== undefined) out[field.key] = addresses(out[field.key])
    if (leftToJarvis(field) && out[field.key] === AUTO) delete out[field.key]
  }
  return out
}

/**
 * A cleaned playbook in the words Jarvis uses (when_to_use, min_away). The
 * page is Dylan's, so what it saves is marked as made by him: Jarvis runs
 * those without asking.
 */
export function toJarvisPlaybook(playbook, stepTypes = DEFAULT_STEP_TYPES) {
  const trigger = { ...playbook.trigger }
  if (trigger.type === 'arrive') {
    trigger.min_away = trigger.minAway
    delete trigger.minAway
  }
  const { whenToUse, edgeCases, badVersion, ...rest } = playbook
  return {
    ...rest,
    when_to_use: whenToUse,
    edge_cases: edgeCases,
    bad_version: badVersion,
    trigger,
    steps: playbook.steps.map((step) => toJarvisStep(step, stepTypes)),
    made_by: 'dylan',
  }
}

/** One step from Jarvis in the page's shape; null when it has no usable type. */
function fromJarvisStep(raw, stepTypes) {
  // "ask" is the older name for a thinking step.
  const step = plainStep(raw?.type === 'ask' ? { ...raw, type: 'think' } : raw)
  if (step === null) return null
  // Fixed steps carry Jarvis's own "code" tag, which the page doesn't need.
  if (step.model === 'code') delete step.model
  const fields = stepTypes.find((t) => t.type === step.type)?.fields ?? []
  for (const field of fields) {
    if (field.kind === 'emails' && step[field.key] !== undefined) step[field.key] = addresses(step[field.key]).join(', ')
    if (field.kind === 'bool') step[field.key] = step[field.key] === true
    if (leftToJarvis(field) && step[field.key] === undefined) step[field.key] = AUTO
  }
  return step
}

/** How one done item came out on the last run; null when it isn't one. */
function toCheck(raw) {
  if (typeof raw?.item !== 'string' || !raw.item) return null
  return { item: raw.item, ok: raw.ok !== false, why: typeof raw.why === 'string' ? raw.why : '' }
}

/** One playbook from Jarvis, in the page's shape; null when it isn't one. */
export function fromJarvisPlaybook(raw, stepTypes = DEFAULT_STEP_TYPES) {
  if (typeof raw?.id !== 'string' || typeof raw?.name !== 'string') return null
  const trigger = { ...(raw.trigger ?? { type: 'manual' }) }
  if (trigger.type === 'arrive') {
    trigger.minAway = Number(trigger.min_away) || 0
    delete trigger.min_away
  }
  if (trigger.type === 'time' && !Array.isArray(trigger.days)) trigger.days = []
  // An older Jarvis calls the steps "actions".
  const steps = Array.isArray(raw.steps) ? raw.steps : raw.actions
  const playbook = {
    id: raw.id,
    name: raw.name,
    enabled: raw.enabled !== false,
    purpose: text(raw.purpose, 200),
    whenToUse: text(raw.when_to_use, 500),
    trigger,
    inputs: pairs(raw.inputs, 'name', 'where'),
    steps: Array.isArray(steps) ? steps.map((step) => fromJarvisStep(step, stepTypes)).filter((s) => s !== null) : [],
    decisions: pairs(raw.decisions, 'if', 'then'),
    done: lines(raw.done),
    edgeCases: lines(raw.edge_cases),
    standard: text(raw.standard, 500),
    badVersion: text(raw.bad_version, 500),
    madeBy: raw.made_by === 'jarvis' ? 'jarvis' : 'dylan',
  }
  const last = raw.last_run
  if (last && typeof last.at === 'string') {
    playbook.lastRun = {
      at: last.at,
      ok: last.ok !== false,
      detail: typeof last.detail === 'string' ? last.detail : '',
      checks: parseChecks(last.checks),
    }
  }
  return playbook
}

/**
 * A playbook Jarvis drafted from a description (POST /playbooks/draft), as
 * the editor's draft: no id, no author, no last run. Null when it isn't one.
 */
export function fromJarvisDraft(raw, stepTypes = DEFAULT_STEP_TYPES) {
  if (raw === null || typeof raw !== 'object') return null
  const playbook = fromJarvisPlaybook({ ...raw, id: 'draft' }, stepTypes)
  if (playbook === null) return null
  delete playbook.id
  delete playbook.madeBy
  delete playbook.lastRun
  return playbook
}

/** A run's done checklist from Jarvis, keeping only the well-formed items. */
export function parseChecks(value) {
  if (!Array.isArray(value)) return []
  return value.map(toCheck).filter((c) => c !== null)
}

/** A list of {entity, name, ...} rows from Jarvis, keeping only the well-formed ones. */
function named(rows, extra) {
  if (!Array.isArray(rows)) return []
  return rows
    .filter((r) => typeof r?.entity === 'string' && r.entity)
    .map((r) => ({ entity: r.entity, name: typeof r.name === 'string' && r.name ? r.name : r.entity, ...extra(r) }))
}

/** A list of strings, or [] when Jarvis sent something else. */
function strings(value) {
  return Array.isArray(value) ? value.filter((v) => typeof v === 'string') : []
}

/** Everything the Playbooks page needs from Jarvis's GET /playbooks: the playbooks, the kinds of step and what steps can use. */
export function parsePlaybookBook(body) {
  const options = body?.options ?? {}
  const stepTypes = parseStepTypes(options.step_types) ?? DEFAULT_STEP_TYPES
  const playbooks = Array.isArray(body?.playbooks) ? body.playbooks.map((p) => fromJarvisPlaybook(p, stepTypes)).filter((r) => r !== null) : []
  const thinkers = parseNamed(options.thinkers)
  return {
    playbooks,
    options: {
      devices: named(options.devices, (r) => ({ kind: typeof r.kind === 'string' ? r.kind : '', commands: strings(r.commands) })),
      scenes: named(options.scenes, () => ({})),
      apps: named(options.apps, (r) => ({ apps: strings(r.apps) })),
      zones: strings(options.zones),
      jobs: parseNamed(options.jobs),
      thinkers: thinkers.length > 0 ? thinkers : DEFAULT_THINKERS,
      stepTypes,
    },
  }
}
