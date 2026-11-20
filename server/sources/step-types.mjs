// What kinds of step a playbook can have, as Jarvis describes them
// (GET /playbooks options.step_types; Dylan, 2026-11-20: the page draws what
// Jarvis lists instead of keeping its own list). Each type has a label, a
// one-line summary pattern and its fields; the page builds the editor boxes,
// the row text and the "what's missing" check from this alone, so a new step
// kind in Jarvis shows up with no page change.
//
// DEFAULT_STEP_TYPES is what the page falls back to for a Jarvis too old to
// send the list, and what the mock source serves.

const FIELD_KINDS = ['text', 'longtext', 'number', 'bool', 'choice', 'emails', 'by_command']
const NAME = /^[a-z][a-z0-9_]{0,39}$/
const MAX_TYPES = 40
const MAX_FIELDS = 12

/** A trimmed string no longer than max, or undefined when it isn't one. */
function words(value, max = 200) {
  if (typeof value !== 'string' || value.trim() === '') return undefined
  return value.trim().slice(0, max)
}

/** A finite number, or undefined. */
function number(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

/** A list of short strings, or undefined when it isn't a list. */
function stringList(value) {
  if (!Array.isArray(value)) return undefined
  return value.filter((v) => typeof v === 'string' && v !== '').map((v) => v.slice(0, 80)).slice(0, 40)
}

/** An object without its undefined entries, so the JSON stays small. */
function compact(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined))
}

/**
 * The parts every field shares, in the page's camelCase. `raw` is Jarvis's
 * snake_case field (or one sub-field of a by_command field).
 */
function fieldBody(raw) {
  const kind = FIELD_KINDS.includes(raw?.kind) ? raw.kind : null
  if (kind === null) return null
  const fallback = raw.default
  const hasDefault = typeof fallback === 'string' || typeof fallback === 'boolean' || number(fallback) !== undefined
  return compact({
    label: words(raw.label, 80) ?? '',
    kind,
    required: raw.required === true,
    min: number(raw.min),
    max: number(raw.max),
    step: number(raw.step),
    maxItems: number(raw.max_items),
    placeholder: words(raw.placeholder, 120),
    default: hasDefault ? fallback : undefined,
    choices: stringList(raw.choices),
    choicesFrom: NAME.test(raw.choices_from ?? '') ? raw.choices_from : undefined,
    dependsOn: NAME.test(raw.depends_on ?? '') ? raw.depends_on : undefined,
    choicesKey: NAME.test(raw.choices_key ?? '') ? raw.choices_key : undefined,
    onlyDomains: stringList(raw.only_domains),
  })
}

/** One field of a step type; null when it isn't well formed. */
function parseField(raw) {
  if (!NAME.test(raw?.key ?? '')) return null
  const body = fieldBody(raw)
  if (body === null) return null
  const field = { key: raw.key, ...body }
  if (body.kind === 'by_command') {
    // The value's shape depends on another field's pick: one sub-field per pick that takes a value.
    const byCommand = {}
    for (const [command, sub] of Object.entries(raw.by_command ?? {})) {
      const subBody = fieldBody(sub)
      if (NAME.test(command) && subBody !== null && subBody.kind !== 'by_command') byCommand[command] = subBody
    }
    field.byCommand = byCommand
  }
  return field
}

/** One step type; null when it isn't well formed. */
function parseType(raw) {
  if (!NAME.test(raw?.type ?? '') || !Array.isArray(raw.fields)) return null
  const label = words(raw.label, 80) ?? raw.type
  return {
    type: raw.type,
    label,
    short: words(raw.short, 24) ?? label,
    runs: raw.runs === 'thinking' ? 'thinking' : 'code',
    summary: words(raw.summary, 200) ?? label,
    fields: raw.fields.map(parseField).filter((f) => f !== null).slice(0, MAX_FIELDS),
  }
}

/**
 * Jarvis's step_types list in the page's shape, dropping anything broken.
 * Null when he sent none (an older Jarvis), so the caller can fall back.
 */
export function parseStepTypes(raw) {
  if (!Array.isArray(raw)) return null
  const types = raw.map(parseType).filter((t) => t !== null).slice(0, MAX_TYPES)
  return types.length > 0 ? types : null
}

/** A list of {id, name} rows (jobs, thinkers), keeping only the well-formed ones. */
export function parseNamed(rows) {
  if (!Array.isArray(rows)) return []
  return rows
    .filter((r) => typeof r?.id === 'string' && r.id)
    .map((r) => ({ id: r.id, name: words(r.name, 200) ?? r.id }))
}

// Who can do a thinking step, when Jarvis doesn't say.
export const DEFAULT_THINKERS = [
  { id: 'worker', name: 'Ornith (simple, stays on the PC)' },
  { id: 'claude', name: 'Claude (judgment and writing)' },
]

// The step types Jarvis had on 2026-11-20, as he describes them.
export const DEFAULT_STEP_TYPES = parseStepTypes([
  {
    type: 'device', label: 'Control a device', short: 'Device', runs: 'code', summary: '{entity.name}: {command} {value}',
    fields: [
      { key: 'entity', label: 'Device', kind: 'choice', required: true, choices_from: 'devices' },
      { key: 'command', label: 'Do', kind: 'choice', required: true, choices_from: 'devices', depends_on: 'entity', choices_key: 'commands' },
      {
        key: 'value', label: 'Value', kind: 'by_command', depends_on: 'command',
        by_command: {
          turn_on: { label: 'Brightness %', kind: 'number', required: false, min: 1, max: 100, only_domains: ['light'] },
          volume_set: { label: 'Volume (0 to 1)', kind: 'number', required: true, min: 0, max: 1, step: 0.05 },
          select_source: { label: 'App or input', kind: 'choice', required: true, choices_from: 'apps', depends_on: 'entity', choices_key: 'apps' },
          set_temperature: { label: 'Temperature (°F)', kind: 'number', required: true, min: 45, max: 90 },
          set_hvac_mode: { label: 'Mode', kind: 'choice', required: true, choices: ['off', 'heat', 'cool', 'heat_cool', 'auto'] },
        },
      },
    ],
  },
  { type: 'scene', label: 'Run a scene', short: 'Scene', runs: 'code', summary: 'Scene: {entity.name}', fields: [{ key: 'entity', label: 'Scene', kind: 'choice', required: true, choices_from: 'scenes' }] },
  {
    type: 'app', label: 'Open an app on a TV', short: 'TV app', runs: 'code', summary: 'Open {app} on {entity.name}',
    fields: [
      { key: 'entity', label: 'TV', kind: 'choice', required: true, choices_from: 'apps' },
      { key: 'app', label: 'App', kind: 'choice', required: true, choices_from: 'apps', depends_on: 'entity', choices_key: 'apps' },
    ],
  },
  { type: 'notify', label: 'Send me a notification', short: 'Notify me', runs: 'code', summary: 'Notify me: {text}', fields: [{ key: 'text', label: 'Message', kind: 'longtext', required: true, max: 2000, placeholder: 'What to tell me' }] },
  {
    type: 'think', label: 'Have Jarvis work something out', short: 'Ask Jarvis', runs: 'thinking', summary: 'Jarvis: {text}',
    fields: [
      { key: 'text', label: 'What Jarvis should do', kind: 'longtext', required: true, max: 2000, placeholder: 'Check tomorrow’s weather and tell me if I need a jacket' },
      { key: 'model', label: 'Who does it', kind: 'choice', required: false, choices_from: 'thinkers', default: 'claude' },
      { key: 'confirm', label: 'Ask me first', kind: 'bool', required: false, default: false },
    ],
  },
  {
    type: 'email', label: 'Send an email', short: 'Email', runs: 'code', summary: 'Email {to}: {subject}',
    fields: [
      { key: 'to', label: 'To', kind: 'emails', required: true, max_items: 10 },
      { key: 'subject', label: 'Subject', kind: 'text', required: true, max: 200 },
      { key: 'body', label: 'Message', kind: 'longtext', required: true, max: 5000 },
      { key: 'confirm', label: 'Ask me first', kind: 'bool', required: false, default: false },
    ],
  },
  { type: 'wait', label: 'Wait', short: 'Wait', runs: 'code', summary: 'Wait {seconds} s', fields: [{ key: 'seconds', label: 'Seconds', kind: 'number', required: true, min: 1, max: 600, default: 60 }] },
  { type: 'job', label: 'Run one of Jarvis’s jobs', short: 'Jarvis job', runs: 'code', summary: 'Run: {job.name}', fields: [{ key: 'job', label: 'Job', kind: 'choice', required: true, choices_from: 'jobs' }] },
])

/**
 * The field that applies to a step right now: a by_command field becomes
 * the sub-field for the picked command, or null when that command takes no
 * value (or only does for another kind of device, `domain`).
 */
export function activeField(field, step, domain) {
  if (field.kind !== 'by_command') return field
  const picked = step[field.dependsOn]
  const sub = typeof picked === 'string' ? field.byCommand?.[picked] : undefined
  if (!sub) return null
  if (sub.onlyDomains && !sub.onlyDomains.includes(domain)) return null
  return { key: field.key, ...sub }
}
