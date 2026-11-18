// Routines: groups of steps Jarvis runs by himself at a set time, when you
// arrive or leave, when you go to sleep or wake up, or only when you tap
// Run (Dylan, 2026-11-18). Jarvis owns and runs them (GET/POST /routines);
// this file checks what the page sends before it's passed on, and turns
// Jarvis's snake_case into the page's shape and back.

export const ROUTINE_DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
const TRIGGER_TYPES = ['time', 'arrive', 'leave', 'asleep', 'awake', 'manual']
const MAX_ACTIONS = 20
const MAX_TEXT = 2000
const MAX_BODY = 5000
const MAX_TO = 10
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

/** A trimmed string no longer than max, or '' when it isn't a string. */
function text(value, max = 200) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, max)
}

/** The trigger as the page sent it, cleaned; null when it makes no sense. */
function cleanTrigger(raw) {
  if (!raw || !TRIGGER_TYPES.includes(raw.type)) return null
  if (raw.type === 'time') {
    if (typeof raw.at !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(raw.at)) return null
    const days = Array.isArray(raw.days) ? ROUTINE_DAYS.filter((d) => raw.days.includes(d)) : []
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
function cleanAction(raw) {
  if (!raw || typeof raw.type !== 'string') return null
  if (raw.type === 'device') {
    const entity = text(raw.entity)
    const command = text(raw.command, 40)
    if (!entity || !command) return null
    const action = { type: 'device', entity, command }
    if (typeof raw.value === 'number' && Number.isFinite(raw.value)) action.value = raw.value
    if (typeof raw.value === 'string' && raw.value.trim()) action.value = text(raw.value, 60)
    return action
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
  if (raw.type === 'ask') {
    const words = text(raw.text, MAX_TEXT)
    // Asking first is the default; only an explicit false turns it off.
    return words ? { type: 'ask', text: words, confirm: raw.confirm !== false } : null
  }
  if (raw.type === 'email') {
    // One address, or several split by commas (Jarvis takes up to ten).
    const to = text(raw.to, 1000).split(',').map((a) => a.trim()).filter((a) => a !== '')
    const subject = text(raw.subject, 200)
    const body = text(raw.body, MAX_BODY)
    if (to.length === 0 || to.length > MAX_TO || !to.every((a) => EMAIL.test(a)) || !subject || !body) return null
    return { type: 'email', to: to.join(', '), subject, body, confirm: raw.confirm !== false }
  }
  if (raw.type === 'wait') {
    const seconds = Number(raw.seconds)
    if (!Number.isFinite(seconds) || seconds < 1) return null
    return { type: 'wait', seconds: Math.min(600, Math.round(seconds)) }
  }
  return null
}

/**
 * A routine as the page sent it, checked and trimmed. Returns
 * {routine} when it's fine, or {problem} saying in plain words what's wrong.
 */
export function cleanRoutine(raw) {
  const name = text(raw?.name, 60)
  if (!name) return { problem: 'Give the routine a name' }
  const trigger = cleanTrigger(raw?.trigger)
  if (!trigger) return { problem: 'Pick when the routine should run' }
  if (!Array.isArray(raw?.actions) || raw.actions.length === 0) return { problem: 'Add at least one step' }
  if (raw.actions.length > MAX_ACTIONS) return { problem: `A routine can have up to ${MAX_ACTIONS} steps` }
  const actions = raw.actions.map(cleanAction)
  const bad = actions.findIndex((a) => a === null)
  if (bad >= 0) return { problem: `Step ${bad + 1} is missing something` }
  const routine = { name, enabled: raw.enabled !== false, trigger, actions }
  const id = text(raw?.id, 80)
  if (id) routine.id = id
  return { routine }
}

/** A cleaned routine in the words Jarvis uses (min_away, not minAway; email "to" as a list). */
export function toJarvisRoutine(routine) {
  const trigger = { ...routine.trigger }
  if (trigger.type === 'arrive') {
    trigger.min_away = trigger.minAway
    delete trigger.minAway
  }
  const actions = routine.actions.map((a) => (a.type === 'email' ? { ...a, to: a.to.split(', ') } : a))
  return { ...routine, trigger, actions }
}

/** One step from Jarvis in the page's shape: an email's list of addresses becomes one line. */
function fromJarvisAction(raw) {
  if (raw.type === 'email' && Array.isArray(raw.to)) return { ...raw, to: strings(raw.to).join(', ') }
  return raw
}

/** One routine from Jarvis, in the page's shape; null when it isn't one. */
export function fromJarvisRoutine(raw) {
  if (typeof raw?.id !== 'string' || typeof raw?.name !== 'string') return null
  const trigger = { ...(raw.trigger ?? { type: 'manual' }) }
  if (trigger.type === 'arrive') {
    trigger.minAway = Number(trigger.min_away) || 0
    delete trigger.min_away
  }
  if (trigger.type === 'time' && !Array.isArray(trigger.days)) trigger.days = []
  const routine = {
    id: raw.id,
    name: raw.name,
    enabled: raw.enabled !== false,
    trigger,
    actions: Array.isArray(raw.actions) ? raw.actions.filter((a) => typeof a?.type === 'string').map(fromJarvisAction) : [],
  }
  const last = raw.last_run
  if (last && typeof last.at === 'string') {
    routine.lastRun = { at: last.at, ok: last.ok !== false, detail: typeof last.detail === 'string' ? last.detail : '' }
  }
  return routine
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

/** Everything the Routines page needs from Jarvis's GET /routines: the routines and what steps can use. */
export function parseRoutineBook(body) {
  const routines = Array.isArray(body?.routines) ? body.routines.map(fromJarvisRoutine).filter((r) => r !== null) : []
  const options = body?.options ?? {}
  return {
    routines,
    options: {
      devices: named(options.devices, (r) => ({ kind: typeof r.kind === 'string' ? r.kind : '', commands: strings(r.commands) })),
      scenes: named(options.scenes, () => ({})),
      apps: named(options.apps, (r) => ({ apps: strings(r.apps) })),
      zones: strings(options.zones),
    },
  }
}
