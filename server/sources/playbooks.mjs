// Playbooks: jobs Jarvis knows how to do (Dylan, 2026-11-18). Each has what
// it's for, when it runs (a set time, arriving or leaving, going to sleep or
// waking, or only when asked), its steps, the rules behind the decisions and
// a done checklist he checks himself against. Jarvis owns and runs them
// (GET/POST /playbooks); this file checks what the page sends before it's
// passed on, and turns Jarvis's snake_case into the page's shape and back.

export const PLAYBOOK_DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
const TRIGGER_TYPES = ['time', 'arrive', 'leave', 'asleep', 'awake', 'manual']
const THINKERS = ['auto', 'worker', 'claude']
const MAX_STEPS = 20
const MAX_LINES = 10
const MAX_TEXT = 2000
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

/** One step, cleaned; null when it's missing what it needs. */
function cleanStep(raw) {
  if (!raw || typeof raw.type !== 'string') return null
  if (raw.type === 'device') {
    const entity = text(raw.entity)
    const command = text(raw.command, 40)
    if (!entity || !command) return null
    const step = { type: 'device', entity, command }
    if (typeof raw.value === 'number' && Number.isFinite(raw.value)) step.value = raw.value
    if (typeof raw.value === 'string' && raw.value.trim()) step.value = text(raw.value, 60)
    return step
  }
  if (raw.type === 'scene') {
    const entity = text(raw.entity)
    return entity ? { type: 'scene', entity } : null
  }
  if (raw.type === 'app') {
    const entity = text(raw.entity)
    const app = text(raw.app, 80)
    return entity && app ? { type: 'app', entity, app } : null
  }
  if (raw.type === 'notify') {
    const words = text(raw.text, MAX_TEXT)
    return words ? { type: 'notify', text: words } : null
  }
  if (raw.type === 'think') {
    const words = text(raw.text, MAX_TEXT)
    if (!words) return null
    return { type: 'think', text: words, model: THINKERS.includes(raw.model) ? raw.model : 'auto' }
  }
  if (raw.type === 'email') {
    // One address, or several split by commas (Jarvis takes up to ten).
    const to = text(raw.to, 1000).split(',').map((a) => a.trim()).filter((a) => a !== '')
    const subject = text(raw.subject, 200)
    const body = text(raw.body, MAX_BODY)
    if (to.length === 0 || to.length > MAX_TO || !to.every((a) => EMAIL.test(a)) || !subject || !body) return null
    // A playbook Dylan wrote doesn't ask before sending; only an explicit true turns asking on.
    return { type: 'email', to: to.join(', '), subject, body, confirm: raw.confirm === true }
  }
  if (raw.type === 'wait') {
    const seconds = Number(raw.seconds)
    if (!Number.isFinite(seconds) || seconds < 1) return null
    return { type: 'wait', seconds: Math.min(600, Math.round(seconds)) }
  }
  return null
}

/**
 * A playbook as the page sent it, checked and trimmed. Returns
 * {playbook} when it's fine, or {problem} saying in plain words what's wrong.
 */
export function cleanPlaybook(raw) {
  const name = text(raw?.name, 60)
  if (!name) return { problem: 'Give the playbook a name' }
  const trigger = cleanTrigger(raw?.trigger)
  if (!trigger) return { problem: 'Pick when the playbook should run' }
  if (!Array.isArray(raw?.steps) || raw.steps.length === 0) return { problem: 'Add at least one step' }
  if (raw.steps.length > MAX_STEPS) return { problem: `A playbook can have up to ${MAX_STEPS} steps` }
  const steps = raw.steps.map(cleanStep)
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

/** One cleaned step in the words Jarvis uses: an email's addresses as a list, no model when he's to pick. */
function toJarvisStep(step) {
  if (step.type === 'email') return { ...step, to: step.to.split(', ') }
  if (step.type === 'think' && step.model === 'auto') return { type: 'think', text: step.text }
  return step
}

/**
 * A cleaned playbook in the words Jarvis uses (when_to_use, min_away). The
 * page is Dylan's, so what it saves is marked as made by him: Jarvis runs
 * those without asking.
 */
export function toJarvisPlaybook(playbook) {
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
    steps: playbook.steps.map(toJarvisStep),
    made_by: 'dylan',
  }
}

/** One step from Jarvis in the page's shape; null when it isn't one the page knows. */
function fromJarvisStep(raw) {
  if (typeof raw?.type !== 'string') return null
  if (raw.type === 'email') {
    const to = Array.isArray(raw.to) ? strings(raw.to).join(', ') : text(raw.to, 1000)
    return { type: 'email', to, subject: text(raw.subject, 200), body: text(raw.body, MAX_BODY), confirm: raw.confirm === true }
  }
  // "ask" is the older name for a thinking step.
  if (raw.type === 'think' || raw.type === 'ask') {
    const model = raw.model === 'worker' || raw.model === 'claude' ? raw.model : 'auto'
    return { type: 'think', text: text(raw.text, MAX_TEXT), model }
  }
  // Fixed steps carry Jarvis's own "code" tag, which the page doesn't need.
  const { model: _model, ...step } = raw
  return step
}

/** How one done item came out on the last run; null when it isn't one. */
function toCheck(raw) {
  if (typeof raw?.item !== 'string' || !raw.item) return null
  return { item: raw.item, ok: raw.ok !== false, why: typeof raw.why === 'string' ? raw.why : '' }
}

/** One playbook from Jarvis, in the page's shape; null when it isn't one. */
export function fromJarvisPlaybook(raw) {
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
    steps: Array.isArray(steps) ? steps.map(fromJarvisStep).filter((s) => s !== null) : [],
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
export function fromJarvisDraft(raw) {
  if (raw === null || typeof raw !== 'object') return null
  const playbook = fromJarvisPlaybook({ ...raw, id: 'draft' })
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

/** Everything the Playbooks page needs from Jarvis's GET /playbooks: the playbooks and what steps can use. */
export function parsePlaybookBook(body) {
  const playbooks = Array.isArray(body?.playbooks) ? body.playbooks.map(fromJarvisPlaybook).filter((r) => r !== null) : []
  const options = body?.options ?? {}
  return {
    playbooks,
    options: {
      devices: named(options.devices, (r) => ({ kind: typeof r.kind === 'string' ? r.kind : '', commands: strings(r.commands) })),
      scenes: named(options.scenes, () => ({})),
      apps: named(options.apps, (r) => ({ apps: strings(r.apps) })),
      zones: strings(options.zones),
    },
  }
}
