import type { Playbook, PlaybookDay, PlaybookDraft, PlaybookOptions, PlaybookStep, PlaybookThinker, PlaybookTrigger } from '../types'

// Words and starting values for the Playbooks page: how a trigger and a
// step read in a sentence, what a new playbook or step starts as, and what's
// still missing before one can be saved. The server checks again
// (server/sources/playbooks.mjs); this copy is so the page can say what's
// wrong before anything is sent.

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

// `label` heads a step; `short` is its button in the editor's "Add a step" row.
export const STEP_CHOICES: { type: PlaybookStep['type']; label: string; short: string }[] = [
  { type: 'device', label: 'Control a device', short: 'Device' },
  { type: 'scene', label: 'Run a scene', short: 'Scene' },
  { type: 'app', label: 'Open an app on a TV', short: 'TV app' },
  { type: 'notify', label: 'Send me a notification', short: 'Notify me' },
  { type: 'think', label: 'Have Jarvis work something out', short: 'Ask Jarvis' },
  { type: 'email', label: 'Send an email', short: 'Email' },
  { type: 'wait', label: 'Wait', short: 'Wait' },
  { type: 'job', label: 'Run one of Jarvis’s own jobs', short: 'Jarvis job' },
]

/** The step kinds the editor can add: a job step only when Jarvis lists jobs. */
export function stepChoices(options: PlaybookOptions) {
  return STEP_CHOICES.filter((c) => c.type !== 'job' || options.jobs.length > 0)
}

/** A job's name as Jarvis gave it, or its id when he doesn't list it. */
export function jobName(id: string, options: PlaybookOptions): string {
  return options.jobs.find((j) => j.id === id)?.name ?? id
}

// Who does a thinking step, as the editor offers it.
export const THINKER_CHOICES: { model: PlaybookThinker; label: string }[] = [
  { model: 'auto', label: 'Jarvis picks' },
  { model: 'worker', label: 'Ornith (simple, stays on the PC)' },
  { model: 'claude', label: 'Claude (judgment and writing)' },
]

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
export function stepLine(step: PlaybookStep, options: PlaybookOptions): string {
  if (step.type === 'device') {
    const name = nameOf(step.entity, options.devices)
    if (step.value === undefined) return `${commandLabel(step.command)}: ${name}`
    return `${name}: ${commandLabel(step.command).toLowerCase()} ${step.value}`
  }
  if (step.type === 'scene') return `Scene: ${nameOf(step.entity, options.scenes)}`
  if (step.type === 'app') return `Open ${step.app} on ${nameOf(step.entity, options.apps)}`
  if (step.type === 'notify') return `Notify me: ${clip(step.text)}`
  if (step.type === 'think') return `Jarvis: ${clip(step.text)}`
  if (step.type === 'email') return `Email ${step.to}: ${clip(step.subject)}`
  if (step.type === 'job') return `Run: ${clip(jobName(step.job, options))}`
  if (step.seconds % 60 === 0) return `Wait ${step.seconds / 60} min`
  return `Wait ${step.seconds} s`
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

/** What a step of one type starts as: the first device, scene or app Jarvis lists. */
export function blankStep(type: PlaybookStep['type'], options: PlaybookOptions): PlaybookStep {
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
  if (type === 'think') return { type, text: '', model: 'auto' }
  // A playbook you wrote doesn't ask before sending (Dylan, 2026-11-18).
  if (type === 'email') return { type, to: '', subject: '', body: '', confirm: false }
  if (type === 'job') return { type, job: options.jobs[0]?.id ?? '' }
  return { type, seconds: 60 }
}

/** What one step is still missing, or null when it's complete. */
function stepProblem(step: PlaybookStep): string | null {
  if (step.type === 'device') {
    if (!step.entity) return 'pick a device'
    if (commandTakesValue(step.command) && (step.value === undefined || step.value === '')) return 'give it a value'
    return null
  }
  if (step.type === 'scene') return step.entity ? null : 'pick a scene'
  if (step.type === 'app') return step.entity && step.app ? null : 'pick a TV and an app'
  if (step.type === 'notify') return step.text.trim() ? null : 'write what it should say'
  if (step.type === 'think') return step.text.trim() ? null : 'write what Jarvis should do'
  if (step.type === 'job') return step.job ? null : 'pick a job'
  if (step.type === 'email') {
    const addresses = emailAddresses(step.to)
    if (addresses.length === 0 || addresses.length > 10) return 'give it one to ten email addresses'
    if (!addresses.every((a) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(a))) return 'check the email address'
    if (!step.subject.trim() || !step.body.trim()) return 'write a subject and a message'
    return null
  }
  if (step.seconds < 1 || step.seconds > 600) return 'wait between 1 and 600 seconds'
  return null
}

/** Why a playbook can't be saved yet, in plain words; null when it can. */
export function playbookProblem(draft: PlaybookDraft): string | null {
  if (!draft.name.trim()) return 'Give the playbook a name'
  if (draft.trigger.type === 'time' && !/^([01]\d|2[0-3]):[0-5]\d$/.test(draft.trigger.at)) return 'Pick a time'
  if (draft.steps.length === 0) return 'Add at least one step'
  for (let i = 0; i < draft.steps.length; i += 1) {
    const problem = stepProblem(draft.steps[i])
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
