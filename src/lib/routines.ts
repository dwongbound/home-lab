import type { RoutineAction, RoutineDay, RoutineDraft, RoutineOptions, RoutineTrigger } from '../types'

// Words and starting values for the Routines page: how a trigger and a
// step read in a sentence, what a new routine or step starts as, and what's
// still missing before one can be saved. The server checks again
// (server/sources/routines.mjs); this copy is so the page can say what's
// wrong before anything is sent.

export const DAYS: { id: RoutineDay; label: string }[] = [
  { id: 'mon', label: 'Mon' },
  { id: 'tue', label: 'Tue' },
  { id: 'wed', label: 'Wed' },
  { id: 'thu', label: 'Thu' },
  { id: 'fri', label: 'Fri' },
  { id: 'sat', label: 'Sat' },
  { id: 'sun', label: 'Sun' },
]

export const TRIGGER_CHOICES: { type: RoutineTrigger['type']; label: string }[] = [
  { type: 'time', label: 'At a time' },
  { type: 'arrive', label: 'When I get home' },
  { type: 'leave', label: 'When I leave home' },
  { type: 'asleep', label: 'When I go to sleep' },
  { type: 'awake', label: 'When I wake up' },
  { type: 'manual', label: 'Only when I tap Run' },
]

export const ACTION_CHOICES: { type: RoutineAction['type']; label: string }[] = [
  { type: 'device', label: 'Control a device' },
  { type: 'scene', label: 'Run a scene' },
  { type: 'app', label: 'Open an app on a TV' },
  { type: 'notify', label: 'Send me a notification' },
  { type: 'ask', label: 'Ask Jarvis to do something' },
  { type: 'email', label: 'Send an email' },
  { type: 'wait', label: 'Wait' },
]

/** "08:30" as "8:30 AM". */
export function clockLabel(at: string): string {
  const [h, m] = at.split(':').map(Number)
  if (!Number.isFinite(h) || !Number.isFinite(m)) return at
  const hour = h % 12 === 0 ? 12 : h % 12
  return `${hour}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`
}

/** Which days a timed routine runs, in words: "every day", "weekdays", "Mon, Wed". */
export function daysLabel(days: RoutineDay[]): string {
  if (days.length === 0 || days.length === 7) return 'every day'
  const has = (d: RoutineDay) => days.includes(d)
  const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri'] as RoutineDay[]
  if (days.length === 5 && weekdays.every(has)) return 'weekdays'
  if (days.length === 2 && has('sat') && has('sun')) return 'weekends'
  return DAYS.filter((d) => has(d.id)).map((d) => d.label).join(', ')
}

/** When a routine runs, as one line. */
export function triggerLine(trigger: RoutineTrigger): string {
  if (trigger.type === 'time') return `At ${clockLabel(trigger.at)}, ${daysLabel(trigger.days)}`
  if (trigger.type === 'arrive') {
    if (trigger.minAway > 0) return `When I get home after ${trigger.minAway} min away`
    return 'When I get home'
  }
  if (trigger.type === 'leave') return 'When I leave home'
  if (trigger.type === 'asleep') return 'When I go to sleep'
  if (trigger.type === 'awake') return 'When I wake up'
  return 'Only when I tap Run'
}

// Jarvis's device commands (Home Assistant service names) in plain words.
const COMMAND_WORDS: Record<string, string> = {
  set_temperature: 'Set temperature to',
  set_hvac_mode: 'Set mode to',
  volume_set: 'Set volume to',
  select_source: 'Open',
  media_play: 'Play',
  media_pause: 'Pause',
  media_stop: 'Stop',
}

// Commands that need a value: a temperature, a mode, a volume from 0 to 1, an app.
const VALUE_COMMANDS = ['set_temperature', 'set_hvac_mode', 'volume_set', 'select_source']

// Commands whose value is words, not a number.
const WORD_COMMANDS = ['set_hvac_mode', 'select_source']

/** A command in plain words: "turn_off" reads "Turn off". */
export function commandLabel(command: string): string {
  const known = COMMAND_WORDS[command]
  if (known) return known
  const words = command.replace(/_/g, ' ')
  return words.charAt(0).toUpperCase() + words.slice(1)
}

/** Whether a command needs a value typed in (a temperature, a volume). */
export function commandTakesValue(command: string): boolean {
  return VALUE_COMMANDS.includes(command)
}

/** Whether a command's value is words (a mode, an app) rather than a number. */
export function commandTakesWords(command: string): boolean {
  return WORD_COMMANDS.includes(command)
}

/** Every address in a "to" box: one, or several split by commas. */
export function emailAddresses(to: string): string[] {
  return to.split(',').map((a) => a.trim()).filter((a) => a !== '')
}

/** The name a step's device, scene or TV goes by; its id when Jarvis no longer lists it. */
function nameOf(entity: string, rows: { entity: string; name: string }[]): string {
  return rows.find((r) => r.entity === entity)?.name ?? entity
}

/** A short piece of typed text for a one-line summary. */
function clip(words: string, max = 48): string {
  if (words.length <= max) return words
  return `${words.slice(0, max - 1).trimEnd()}…`
}

/** One step, as one line. */
export function actionLine(action: RoutineAction, options: RoutineOptions): string {
  if (action.type === 'device') {
    const name = nameOf(action.entity, options.devices)
    if (action.value === undefined) return `${commandLabel(action.command)}: ${name}`
    return `${name}: ${commandLabel(action.command).toLowerCase()} ${action.value}`
  }
  if (action.type === 'scene') return `Scene: ${nameOf(action.entity, options.scenes)}`
  if (action.type === 'app') return `Open ${action.app} on ${nameOf(action.entity, options.apps)}`
  if (action.type === 'notify') return `Notify me: ${clip(action.text)}`
  if (action.type === 'ask') return `Ask Jarvis: ${clip(action.text)}`
  if (action.type === 'email') return `Email ${action.to}: ${clip(action.subject)}`
  if (action.seconds % 60 === 0) return `Wait ${action.seconds / 60} min`
  return `Wait ${action.seconds} s`
}

/** A new, empty routine: runs only from the Run button until a trigger is picked. */
export function blankRoutine(): RoutineDraft {
  return { name: '', enabled: true, trigger: { type: 'manual' }, actions: [] }
}

/** What a trigger of one type starts as when it's picked. */
export function blankTrigger(type: RoutineTrigger['type']): RoutineTrigger {
  if (type === 'time') return { type, at: '08:00', days: [] }
  if (type === 'arrive') return { type, zone: 'home', minAway: 15 }
  if (type === 'leave') return { type, zone: 'home' }
  return { type }
}

/** What a step of one type starts as: the first device, scene or app Jarvis lists. */
export function blankAction(type: RoutineAction['type'], options: RoutineOptions): RoutineAction {
  if (type === 'device') {
    const first = options.devices[0]
    return { type, entity: first?.entity ?? '', command: first?.commands[0] ?? 'turn_off' }
  }
  if (type === 'scene') return { type, entity: options.scenes[0]?.entity ?? '' }
  if (type === 'app') {
    const first = options.apps[0]
    return { type, entity: first?.entity ?? '', app: first?.apps[0] ?? '' }
  }
  if (type === 'notify') return { type, text: '' }
  if (type === 'ask') return { type, text: '', confirm: true }
  if (type === 'email') return { type, to: '', subject: '', body: '', confirm: true }
  return { type, seconds: 60 }
}

/** What one step is still missing, or null when it's complete. */
function actionProblem(action: RoutineAction): string | null {
  if (action.type === 'device') {
    if (!action.entity) return 'pick a device'
    if (commandTakesValue(action.command) && (action.value === undefined || action.value === '')) return 'give it a value'
    return null
  }
  if (action.type === 'scene') return action.entity ? null : 'pick a scene'
  if (action.type === 'app') return action.entity && action.app ? null : 'pick a TV and an app'
  if (action.type === 'notify' || action.type === 'ask') return action.text.trim() ? null : 'write what it should say'
  if (action.type === 'email') {
    const addresses = emailAddresses(action.to)
    if (addresses.length === 0 || addresses.length > 10) return 'give it one to ten email addresses'
    if (!addresses.every((a) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(a))) return 'check the email address'
    if (!action.subject.trim() || !action.body.trim()) return 'write a subject and a message'
    return null
  }
  if (action.seconds < 1 || action.seconds > 600) return 'wait between 1 and 600 seconds'
  return null
}

/** Why a routine can't be saved yet, in plain words; null when it can. */
export function routineProblem(draft: RoutineDraft): string | null {
  if (!draft.name.trim()) return 'Give the routine a name'
  if (draft.trigger.type === 'time' && !/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.trigger.at)) return 'Pick a time'
  if (draft.actions.length === 0) return 'Add at least one step'
  for (let i = 0; i < draft.actions.length; i += 1) {
    const problem = actionProblem(draft.actions[i])
    if (problem) return `Step ${i + 1}: ${problem}`
  }
  return null
}
