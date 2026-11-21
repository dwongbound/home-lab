// The one shape the server hands the page. Mock and live sources both
// produce it (server/sources/*.mjs).
export type ServiceStatus = 'up' | 'idle' | 'degraded' | 'down'
export type RunStatus = 'done' | 'failed' | 'running' | 'scheduled'

export interface Metric {
  id: 'ram' | 'gpu' | 'cpu' | 'disk'
  label: string
  value: number | null
  unit: string
  total: number | null
  history: number[]
}

export interface DayCount { day: string; count: number; today: boolean }
export interface TimelineItem {
  id: string
  at: string
  title: string
  detail: string
  status: RunStatus
  /** Where it came from, on the Overview's combined day; Jarvis when missing. */
  source?: 'calendar' | 'jarvis'
  /** An all-day calendar event: shown as "All day" instead of a time. */
  allDay?: boolean
}
export interface ActivityItem { id: string; at: string; kind: 'jarvis' | 'ha' | 'ollama' | 'system'; text: string }
export interface Service { id: string; name: string; detail: string; status: ServiceStatus; latencyMs?: number; url?: string }

// The cloud digest: what a scheduled Claude task collects from claude.ai
// (project threads) and Dylan's connectors, written to a private repo and
// read by the PC. See docs/digest.md for how it's made.
export type ThreadState = 'working' | 'blocked' | 'review_ready' | 'done' | 'failed' | 'stopped'
export interface ClaudeThread { id: string; title: string; state: ThreadState; lastActivityAt: string; url: string }
export interface CalendarEvent {
  id: string; title: string; start: string; end: string; allDay: boolean; calendar: string
  /** Optional: the event in Google Calendar, and where it is. */
  url?: string; location?: string
}
export interface EmailItem {
  id: string; from: string; subject: string; why: string
  /** Optional: the thread in Gmail. */
  url?: string
}
export interface Deploy { project: string; state: 'ready' | 'building' | 'error'; at: string; url: string }
export interface PullRequest { repo: string; number: number; title: string; ci: 'passing' | 'failing' | 'running' | 'none'; url: string }

// Money, from Dylan's Copilot connector by way of the digest. Amounts are
// US dollars. A balance is what the account holds, except for credit and
// loan accounts, where it's what's owed (positive either way).
export type AccountKind = 'cash' | 'credit' | 'investment' | 'loan' | 'other'
export interface MoneyAccount { id: string; name: string; institution: string; kind: AccountKind; balance: number }
export interface SpendCategory { name: string; spent: number; budget: number | null }
export interface MoneyTransaction {
  id: string; date: string; merchant: string; category: string; amount: number
  /** Optional, when the digest has them: which account, still pending, a note. */
  account?: string; accountId?: string; pending?: boolean; note?: string
  /** Copilot's type, when the digest has it: a transfer between his own accounts needs no category. */
  type?: 'regular' | 'income' | 'transfer'
}
export interface MoneyFlag { id: string; text: string }
export interface MoneyDigest {
  netWorth: number | null
  accounts: MoneyAccount[]
  /** Spent so far this month, and by the same day last month. */
  spending: { thisMonth: number; lastMonthToDate: number | null; budget: number | null }
  categories: SpendCategory[]
  /** Newest first. A negative amount is money coming in (a refund, pay). */
  recent: MoneyTransaction[]
  /** Anything worth a look: a big charge, a new subscription, a low balance. */
  flags: MoneyFlag[]
}

/**
 * A category Dylan picked on the page for a purchase Copilot left unsorted.
 * Copilot's connector is read-only, so these wait on the PC until he
 * applies them all in Copilot and marks them done (server/money-picks.mjs).
 */
export interface MoneyPick { id: string; category: string; merchant: string; date: string; amount: number; pickedAt: string }
export interface MoneyPicks {
  picks: MoneyPick[]
  /** When the page starts reminding him to apply them, or null with none waiting. */
  remindAt: string | null
}
/** One change to the picks, as POST /api/money/picks takes it. */
export type MoneyPickChange =
  | { op: 'pick'; id: string; category: string; merchant: string; date: string; amount: number; remindAt?: string }
  | { op: 'clear'; ids: string[] }
  | { op: 'remind'; at: string }

export interface CloudDigest {
  updatedAt: string
  threads: ClaudeThread[]
  /** When the threads list was last sent (THREADS_FILE), if it came separately from the digest. */
  threadsUpdatedAt?: string
  calendar: CalendarEvent[]
  email: EmailItem[]
  deploys: Deploy[]
  pullRequests: PullRequest[]
  /** Missing until the digest task reads Copilot. */
  money?: MoneyDigest | null
}

// Home Assistant devices for the Home page (server/sources/home.mjs).
export type DeviceKind = 'light' | 'switch' | 'fan' | 'media' | 'scene' | 'script' | 'climate'
export interface Device {
  id: string
  name: string
  kind: DeviceKind
  /** Home Assistant's own state: "on", "off", "playing", "paused", "idle"... */
  state: string
  available: boolean
  /** 0-1, lights only. */
  brightness?: number
  /** 0-1, media players only. */
  volume?: number
  /** What's playing, or the app open; for a thermostat, what it's doing ("heating"). */
  detail?: string
  /** Thermostats only: the room's temperature and the one it's set to, in HA's unit. */
  current?: number
  target?: number
  /** Thermostats only: the room's humidity, percent, when it reports one. */
  humidity?: number
  /** Thermostats only: the lowest and highest target, and how far one press moves it. */
  min?: number
  max?: number
  step?: number
  /** Thermostats only: the modes it offers ("off", "heat", "cool", "heat_cool"...). */
  modes?: string[]
}
/** What a read-only sensor reading is about. */
export type ReadingKind = 'temperature' | 'humidity' | 'door' | 'window' | 'motion' | 'battery'

/** One read-only sensor reading from Home Assistant: a room's temperature, an open door, a low battery. */
export interface Reading {
  id: string
  name: string
  kind: ReadingKind
  /** A number as text ("71.5"), or "open", "detected", "low". */
  value: string
  /** The sensor's own unit ("°F", "%"), numbers only. */
  unit?: string
}

/** One coming hour of weather from Home Assistant. */
export interface ForecastHour {
  /** When the hour starts, ISO. */
  at: string
  /** Home Assistant's weather word ("sunny", "rainy"...). */
  condition: string
  temperature?: number
  low?: number
  /** Chance of rain, percent. */
  rain?: number
}

export interface HomeState {
  devices: Device[]
  /** Sensor readings, the ones needing a look first; missing on an older server. */
  readings?: Reading[]
  /** Watts the smart bulbs and plugs draw right now, added up; missing when nothing reports power. */
  powerWatts?: number
  /** The coming hours, soonest first; empty when the weather service has none, missing on an older server. */
  forecast?: ForecastHour[]
  /** Outside now. Humidity is a percent; wind is in Home Assistant's own unit. */
  weather: { condition: string; temperature: number | null; unit: string; humidity?: number; wind?: number; windUnit?: string } | null
  sun: { rising: string | null; setting: string | null }
}
export type HomeCommand = 'toggle' | 'brightness' | 'power' | 'playpause' | 'volume' | 'run' | 'target' | 'mode'

export interface Snapshot {
  generatedAt: string
  source: 'mock' | 'live'
  host: { name: string; os: string; uptimeSec: number }
  metrics: Metric[]
  requests: DayCount[]
  today: TimelineItem[]
  activity: ActivityItem[]
  services: Service[]
  /** The local model (OLLAMA_MODEL), the model the Load/Unload button acts on, whether or not it's loaded. */
  model: { name: string; loaded: boolean; vramGb: number; loadSeconds: number | null }
  /** Every model Ollama has in memory right now, with what it's there for. */
  models: LoadedModel[]
  /** The graphics card's memory and who holds it; null when nvidia-smi can't be read. */
  gpu: GpuUse | null
  /** null until the digest is set up (no token) or before its first read. */
  cloud: CloudDigest | null
  /** null without a Home Assistant token, or when it doesn't answer. */
  home: HomeState | null
  /** What Jarvis runs in the background (GET /jobs); null on an older Jarvis or when it doesn't answer. */
  jobs: JarvisJobs | null
  /** The reports Jarvis has written (GET /reports); null on an older Jarvis or when it doesn't answer. */
  reports: JarvisReports | null
  /** Money page category picks waiting to be applied in Copilot. */
  moneyPicks: MoneyPicks
  /** Jarvis's greeting and the tasks he offers to do (GET /offers); null on an older Jarvis. */
  offers: JarvisOffers | null
  /** Jarvis's unread notifications, newest first (GET /notices); null on an older Jarvis. */
  notices: Notice[] | null
  /** Today's calories (GET /nutrition/today), for the Watch complication; null on an older Jarvis. */
  nutrition: NutritionToday | null
  /** Last night's sleep and a week's trend (Jarvis GET /health/sleep); null on an older Jarvis or before any night. */
  sleep: SleepSummary | null
}

/** Calories and grams of protein, fat and carbs; null where Jarvis has no number. */
export interface Macros { calories: number | null; protein: number | null; fat: number | null; carbs: number | null }

/** One thing he ate: when, what, how much, and its numbers. */
export interface NutritionItem extends Macros {
  id: string
  /** When it was eaten (ISO). */
  at: string
  name: string
  /** "1 bowl", or null when Jarvis has no portion for it. */
  portion: string | null
  hasPhoto: boolean
}

/** An average and a lowest reading over one night; null where the Watch had none. */
export interface NightRange {
  avg: number | null
  min: number | null
}

/** One night of sleep from the Apple Watch, as Jarvis stores and scores it (GET /api/jarvis/health/sleep). */
export interface SleepNight {
  /** The date of the morning it ended, Pacific time. */
  night: string
  bedtime: string | null
  wake: string | null
  minutes: { asleep: number | null; inBed: number | null; awake: number | null; deep: number | null; rem: number | null; core: number | null; unspecified: number | null }
  /** Awakenings of five minutes or more; null when the night's detail is gone. */
  interruptions: number | null
  vitals: {
    heartRate: NightRange | null
    hrvMs: number | null
    hrvRmssdMs: number | null
    respiratoryRate: number | null
    spo2: NightRange | null
    wristTempC: number | null
    wristTempDeltaC: number | null
    breathingDisturbances: number | null
  }
  /** Out of 100: Jarvis's own estimate unless `scoreSource` is apple. */
  score: number | null
  scoreSource: 'jarvis' | 'apple' | null
  /** The word for the score, as Jarvis says it: 85 great, 70 good, 50 fair, under that poor. */
  scoreBand: 'great' | 'good' | 'fair' | 'poor' | null
  /** Duration out of 50, bedtime consistency out of 30, interruptions out of 20. */
  scoreParts: { duration: number | null; consistency: number | null; interruptions: number | null } | null
  /** The night as a timeline, in time order; empty when Jarvis no longer has the detail. */
  stages: { stage: 'core' | 'deep' | 'rem' | 'awake' | 'unspecified'; start: string; end: string }[]
}

/** Sleep in the snapshot, for Home and the TV carousel: the latest night (no timeline) and up to seven nights' trend, newest first. */
export interface SleepSummary {
  last: Omit<SleepNight, 'stages'>
  trend: { night: string; score: number | null; asleep: number | null }[]
}

/** One day of the meal log for the apps' Diet screen (Jarvis GET /nutrition/day). */
export interface NutritionDay {
  /** The Pacific-time day, "2026-11-18". */
  date: string
  goals: Macros
  /** What the day adds up to, and active calories burned when known. */
  totals: Macros & { burned: number | null }
  /** Earliest first. */
  items: NutritionItem[]
}

/** A week of calories and protein eaten against their goals, for the Diet screen's rings (Jarvis GET /nutrition/week). */
export interface NutritionWeek {
  start: string
  days: { date: string; calories: number | null; goal: number | null; protein: number | null; proteinGoal: number | null; fat: number | null; fatGoal: number | null; carbs: number | null; carbsGoal: number | null }[]
}

/** One meal's picture, or why there isn't one (`gone` = that meal has no photo). */
export type MealPhoto = { ok: true; type: string; bytes: Uint8Array } | { ok: false; gone?: boolean; message: string }

/** A run of days of the meal log, newest first, for the Diet screen's endless list (Jarvis GET /nutrition/days). */
export interface NutritionDays {
  days: NutritionDay[]
  /** The earliest day with anything logged, where the list ends; null when nothing is. */
  earliest: string | null
}

/** Today's food numbers from Jarvis's meal log. Numbers only, never meal names. */
export interface NutritionToday {
  /** The Pacific-time day these are for, "2026-11-18". */
  date: string
  /** Calories eaten so far, and the day's goal. */
  eaten: number
  goal: number
  /** goal minus eaten; negative when over. */
  left: number
  /** Active calories burned (Apple Health), when Jarvis has them. */
  burned: number | null
  /** Protein so far and its goal, in grams. */
  protein: number | null
  proteinGoal: number | null
  /** Grams of fat and carbs eaten today and their daily goals; null on an older Jarvis. */
  fat: number | null
  fatGoal: number | null
  carbs: number | null
  carbsGoal: number | null
}

/** How much a notification asks of Dylan: an answer, a look, or nothing. */
export type NoticeKind = 'need' | 'heads' | 'fyi'

/** One unread notification: a dot on the orb and a row in the shared list. */
export interface Notice {
  id: string
  kind: NoticeKind
  /** "Low clouds likely at Torrance on Thursday morning" */
  title: string
  body: string
  /** Where it came from: an approval, Lookout, a reminder, a service alert, a finished job, a message, or a chat message he kept. */
  source: 'approval' | 'lookout' | 'reminder' | 'alert' | 'job' | 'message' | 'kept'
  created: string | null
  /** The approval a "need" notice is waiting on, for Approve and Deny on its row. */
  approvalId?: string
  /** The chat turn (ChatTurn.id) holding the full message this notice previews; approvals have none. */
  turnId?: number
  /** True once he chose to keep it: it stays until he lets it go, whatever gets cleared. */
  kept?: boolean
}

/** What to keep: a chat message by its turn id, or a notice already on the list. */
export type NoticeKeep = { turnId: number } | { id: string }

/** Which notifications to clear: some, or all. */
export type NoticeClear = { ids: string[] } | { all: true }

/** A device that wants lock-screen notifications. */
export interface PushDevice {
  token: string
  platform: 'ios' | 'tvos' | 'watchos'
  environment: 'sandbox' | 'production'
  bundle: string
  name: string
}

/** One task Jarvis offers to do, shown as a card with Start and Hide. */
export interface JarvisOffer {
  id: string
  /** "Find a cover for your Nov 29 guitar slot" */
  title: string
  /** What he noticed and what he'd do, in plain words. */
  body: string
  /** What Start says to him in the chat. */
  startText: string
  created: string | null
}

/** The greeting line and up to three offers. */
export interface JarvisOffers {
  /** "Well, good morning, Dylan! Tapestry B9 plays at 9 on court 4…", or null. */
  greeting: string | null
  offers: JarvisOffer[]
}

/** One report Jarvis wrote: a self-contained page kept on the PC, opened at /reports/<id>. */
export interface JarvisReport {
  id: string
  title: string
  summary: string
  created: string
  /** When Jarvis deletes it (created + the days kept); null when it's kept for good. */
  expires: string | null
  /** True when it's kept for good. */
  kept: boolean
  /** How many days it's kept for (14, 30 or 90); null when it's kept for good. */
  keepDays: number | null
  bytes: number
}

/** Jarvis's reports newest first, the room they take, and the rules: days kept and the size cap. */
export interface JarvisReports {
  reports: JarvisReport[]
  totalBytes: number
  keepDays: number
  /** The most all reports together may take; 0 when Jarvis doesn't say. */
  maxBytes: number
}

/** A change to one report: keep it for a number of days, for good (`keep: true`) or the usual two weeks (`keep: false`), or delete it now. */
export type ReportChange = { op: 'keep'; id: string; days: 14 | 30 | 90 } | { op: 'keep'; id: string; keep: boolean } | { op: 'delete'; id: string }

/** One of Jarvis's background jobs: Lookout, Messenger, Nightly, or housekeeping. */
export interface JarvisJob {
  id: string
  name: string
  /** main = the three jobs that think; housekeeping = quiet plumbing. */
  group: 'main' | 'housekeeping'
  /** The model it uses, or null when no model is involved. */
  model: string | null
  /** When it runs, in plain words. */
  schedule: string | null
  status: 'ok' | 'running' | 'error' | 'paused'
  lastRun: string | null
  nextRun: string | null
  /** One plain sentence about the last run. */
  lastResult: string | null
}

/** Everything the "What Jarvis is doing" panel shows. */
export interface JarvisJobs {
  generatedAt: string | null
  jobs: JarvisJob[]
  /** What Lookout last checked (tool names), what it's keeping an eye on, and what it held back. */
  lookout: { checks: string[]; watching: string[]; heldBack: { text: string; reason: string | null }[] } | null
  /** Pings sent today against the daily cap, and why it's quiet if it is. */
  messenger: { sentToday: number; cap: number; quiet: string | null } | null
  /** Work Dylan sent to the background (e.g. a change to Jarvis's code), still running or queued. Shown beside the orb on /talk. */
  running: RunningTask[]
  /** Background work that finished today, newest first (the apps' Running page); empty on an older Jarvis. */
  finished: FinishedTask[]
}

/** One piece of background work that ended today. */
export interface FinishedTask {
  id: string
  label: string
  /** live = in use now, failed = didn't make it, nothing = nothing needed changing, stopped = Dylan stopped it part way. */
  state: 'live' | 'failed' | 'nothing' | 'stopped'
  finishedAt: string | null
  /** The model that did it, as on chat turns; null when none did. */
  model: string | null
}

/** One piece of background work Dylan asked for, until it finishes. */
export interface RunningTask {
  id: string
  /** What it is, in a few plain words. */
  label: string
  state: 'running' | 'queued'
  startedAt: string | null
  /** The model doing it, as Jarvis names it on chat turns ("claude-opus-…", an Ornith name); null when no model is. */
  model: string | null
  /** Where it's at right now, in one line ("Writing the change", "Running tests"); null when Jarvis doesn't say. */
  step: string | null
  /** Whether it can be stopped safely right now (the apps' full swipe); false on an older Jarvis. */
  stoppable: boolean
}

/** One holder of graphics card memory: a local model, one of Jarvis's speech models, or the unnamed rest. */
export interface GpuUser {
  name: string
  /** What it's for, in a few plain words. */
  role: string
  mb: number
  kind: 'local' | 'speech' | 'other'
}

/** The graphics card right now. `users` are biggest first and add up to at most `usedMb`; the rest of `totalMb` is free. */
export interface GpuUse {
  totalMb: number
  usedMb: number
  /** How busy the card is, 0 to 100; null when the driver doesn't say. */
  utilization: number | null
  users: GpuUser[]
}

/** One model Ollama has loaded (GET /api/ps), and its job on jarvis. */
export interface LoadedModel {
  name: string
  /** What it's for: chat (a chat model), watch (Jarvis's background triage), or other. */
  role: 'chat' | 'watch' | 'other'
  vramGb: number
  /** When Ollama will unload it if nothing uses it, or null when it stays. */
  until: string | null
  /** From Ollama's details, when it gives them: "9.7B", "Q4_K_M", 8192. */
  parameters: string | null
  quantization: string | null
  contextLength: number | null
}

export interface ActionResult { ok: boolean; message: string }

/**
 * The answer to tapping Approve or Deny. `gone` = that request was already
 * over (answered by voice or on another screen, or timed out), with how it
 * was answered when Jarvis still remembers, so the card can be dropped for good.
 */
export interface ApprovalAnswerResult extends ActionResult {
  gone?: boolean
  answer?: { ok: boolean; by: ApprovalBy; later?: boolean }
}

/** One piece of Jarvis's streamed chat reply: more words, the end, or what went wrong. */
/**
 * Jarvis asking before he writes a file or runs a command on the PC. He
 * waits (up to `expires`) for Approve or Deny from the page, a spoken yes
 * or no in Talk, whichever answers first (Telegram was removed 2026-11-18).
 */
export interface Approval { id: string; tool: string; summary: string; expires: string }
/** Who settled an approval: a tap on the page, a spoken yes or no in Talk, or nobody in time. */
export type ApprovalBy = 'page' | 'voice' | 'timeout'
/** How an approval ended: yes, no, or held for later because he said "wait". */
export type ApprovalOutcome = 'approved' | 'denied' | 'later'
export type ChatEvent =
  | { type: 'delta'; text: string }
  | { type: 'done'; ok: true }
  | { type: 'error'; message: string }
  | { type: 'approval'; approval: Approval }
  /** later: he said "wait", so Jarvis holds the request until he brings it up again. */
  | { type: 'approval_done'; id: string; ok: boolean; by: ApprovalBy; later?: boolean }
  /** Jarvis started a slow lookup (label: "Searching the web."), and when it's over. */
  | { type: 'working'; label: string }
  | { type: 'working_done' }
  /** Which brain is answering: "claude", or "ornith" when he has fallen back to the local model. */
  | { type: 'model'; model: string }
  /** Jarvis's number for the message just sent (ChatTurn.id), said first, so its reply can be found in the history later. */
  | { type: 'turn'; id: number }
  /** A meal photo that looks like one already logged; answered with POST /api/jarvis/chat/meal (the apps show the choices as buttons). */
  | { type: 'meal_question'; key: string; choices: string[] }
/** One saved line of the web chat. model: who wrote one of Jarvis's lines, when known. */
/** `images` = how many photos went with the message (the bytes aren't kept in the history). */
/** One line of the chat. `id` is Jarvis's number for it; `model` is who wrote it, or "notice:reminder" for a message he sent unasked, and then `writer` is the model that wrote that message (none for a plain reminder). */
export interface ChatTurn { role: 'user' | 'jarvis'; text: string; at: string; model?: string; writer?: string; images?: number; id?: number; kept?: boolean }

/** Which part of the chat to fetch: the newest `limit` turns, or the ones just older than `before`, or a window centred on `around` (both turn ids). */
export interface HistoryPage { limit: number; before?: number; around?: number }

/** One page of the chat, oldest first. hasMore: older turns exist; hasNewer: newer ones do (only after `around`); pending: Jarvis is still writing the newest reply. */
export interface ChatHistory { turns: ChatTurn[]; hasMore: boolean; hasNewer: boolean; pending: boolean }

/** One photo on a chat message: its kind and base64 bytes. */
export interface ChatImage { type: string; data: string }
export type ActionName = 'ollama-unload' | 'ollama-load'

/** One thing Jarvis keeps in mind in every conversation (his notes file, never memory.md). */
export interface MemoryFact {
  id: string
  text: string
  /** When he learned it (ISO). */
  learned: string
  /** "nightly" when the 3:30 am pass picked it up from a chat, "you" when Dylan told him. */
  from: 'nightly' | 'you'
}

/** What Jarvis remembers: his facts, plus how much past conversation he can search. */
export interface JarvisMemory {
  facts: MemoryFact[]
  /** Conversation turns saved for search. */
  turns: number
  /** When the nightly pass last ran (ISO), if it has. */
  lastDistill: string | null
}

/** One past moment a memory search found. */
export interface MemoryHit { chat: string; role: 'user' | 'jarvis'; text: string; at: string }

/** Adding or forgetting one fact. */
export type MemoryChange = { op: 'remember'; text: string } | { op: 'forget'; id: string }

/** A day of the week a timed playbook runs on. */
export type PlaybookDay = 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun'

/** What starts a playbook: a time, coming or going, bed or waking, or only when asked (or when its job comes up). */
export type PlaybookTrigger =
  | { type: 'time'; at: string; days: PlaybookDay[] }
  | { type: 'arrive'; zone: string; minAway: number }
  | { type: 'leave'; zone: string }
  | { type: 'asleep' }
  | { type: 'awake' }
  | { type: 'manual' }

/** One value of a step: words, a number or yes/no. */
export type StepValue = string | number | boolean

/**
 * One step of a playbook: its kind and that kind's values. Which kinds
 * exist and what each needs comes from Jarvis (`PlaybookOptions.stepTypes`),
 * so the page has no list of its own. A pick left to Jarvis reads 'auto'.
 */
export interface PlaybookStep { type: string; [key: string]: StepValue | undefined }

/** How one box of a step is filled in. `by_command` = its shape depends on another field's pick. */
export type StepFieldKind = 'text' | 'longtext' | 'number' | 'bool' | 'choice' | 'emails' | 'by_command'

/** What a field is, apart from which value of the step it fills. */
export interface StepFieldRule {
  label: string
  kind: StepFieldKind
  required: boolean
  min?: number
  max?: number
  step?: number
  maxItems?: number
  placeholder?: string
  default?: StepValue
  /** Fixed choices, as plain words. */
  choices?: string[]
  /** Or the choices are one of the options lists: devices, scenes, apps, jobs, thinkers. */
  choicesFrom?: string
  /** The field this one hangs off: its pick names the row whose `choicesKey` list is offered. */
  dependsOn?: string
  choicesKey?: string
  /** Only for these kinds of device (a brightness is only for a light). */
  onlyDomains?: string[]
}

/** One field of a step type. */
export interface StepField extends StepFieldRule {
  key: string
  /** For `by_command`: the rule for each pick of `dependsOn` that takes a value. */
  byCommand?: Record<string, StepFieldRule>
}

/** One kind of step, as Jarvis describes it. */
export interface StepType {
  type: string
  /** Heads the step in the editor. */
  label: string
  /** Its button in "Add a step". */
  short: string
  /** Plain code, or a step Jarvis thinks through. */
  runs: 'code' | 'thinking'
  /** The row's one line: "{entity.name}: {command} {value}". */
  summary: string
  fields: StepField[]
}

/** One item of a run's done checklist: whether it held, and why not. */
export interface PlaybookCheck { item: string; ok: boolean; why: string }

/**
 * A job Jarvis knows how to do (Dylan, 2026-11-18): what it's for, when it
 * runs, its steps, the rules behind the decisions, and the checklist he
 * checks himself against after every run.
 */
export interface Playbook {
  id: string
  name: string
  enabled: boolean
  /** What it's for, in one line. */
  purpose: string
  /** When Jarvis should reach for it without being told. */
  whenToUse: string
  trigger: PlaybookTrigger
  /** What it needs, and where each thing lives. */
  inputs: { name: string; where: string }[]
  steps: PlaybookStep[]
  /** The rules behind the judgment calls: if this, then that. */
  decisions: { if: string; then: string }[]
  /** The definition of done: what must be true for a run to count. */
  done: string[]
  /** Things that have gone wrong before. */
  edgeCases: string[]
  /** The tone or quality bar the result has to hit. */
  standard: string
  /** What a bad version looks like. */
  badVersion: string
  /** Who wrote it: Jarvis asks before running one he proposed himself. */
  madeBy: 'dylan' | 'jarvis'
  /** How its last run went, if it has run. */
  lastRun?: { at: string; ok: boolean; detail: string; checks: PlaybookCheck[] }
}

/** A playbook being written: a new one has no id yet. */
export type PlaybookDraft = Omit<Playbook, 'id' | 'lastRun' | 'madeBy'> & { id?: string }

/** The kinds of step and what they can use: devices and their commands, scenes, screens with apps, places, Jarvis's own jobs, who can think. */
export interface PlaybookOptions {
  devices: { entity: string; name: string; kind: string; commands: string[] }[]
  scenes: { entity: string; name: string }[]
  apps: { entity: string; name: string; apps: string[] }[]
  zones: string[]
  jobs: { id: string; name: string }[]
  thinkers: { id: string; name: string }[]
  stepTypes: StepType[]
}

/** Everything the Playbooks page shows. */
export interface PlaybookBook { playbooks: Playbook[]; options: PlaybookOptions }

/** Saving, deleting or running one playbook. */
export type PlaybookChange = { op: 'save'; playbook: PlaybookDraft } | { op: 'delete'; id: string } | { op: 'run'; id: string }

/** Jarvis's go at writing a playbook from a few plain words: the draft to look over (not saved), or why he couldn't. */
export type PlaybookDraftResult = { ok: true; playbook: PlaybookDraft } | { ok: false; message: string }

/** How a change went; a run also says how its done checklist came out. */
export interface PlaybookResult extends ActionResult { checks?: PlaybookCheck[] }

/** One of the voices Jarvis can speak in (Kokoro's built-in set). */
export interface VoiceOption {
  /** Kokoro's id, e.g. "bm_george". */
  id: string
  /** A friendly name, e.g. "George". */
  name: string
  accent: 'us' | 'gb'
  gender: 'f' | 'm'
}

/** Mixing in a second voice: mix is how much of voice2 (0 to 1). */
export interface VoiceBlend { voice2: string; mix: number }

/** How Jarvis sounds: the chosen voice, speed and blend. */
export interface VoiceChoice {
  voice: string
  /** 1 is normal; 0.7 to 1.4. */
  speed: number
  blend: VoiceBlend | null
}

/** His voice settings, plus every voice there is to pick from. */
export interface VoiceSettings extends VoiceChoice { voices: VoiceOption[] }

/** A sample of a voice: WAV bytes on success. */
export type VoiceSample = { ok: true; audio: Uint8Array } | { ok: false; message: string }

/** What both server sources (mock and live) look like from the outside. */
export interface DataSource {
  kind: 'mock' | 'live'
  snapshot(): Promise<Snapshot>
  action(name: ActionName): Promise<ActionResult>
  /** Asks Jarvis. On success `message` is Jarvis's reply. */
  ask(text: string, caller?: { login?: string }): Promise<ActionResult>
  /** Chats with Jarvis, calling onEvent as his reply streams in. */
  chat(text: string, caller: { login?: string; offerId?: string; images?: ChatImage[] }, onEvent: (event: ChatEvent) => void): Promise<void>
  /** The web chat with Jarvis so far, oldest first. */
  history(caller?: { login?: string }, page?: HistoryPage): Promise<ChatHistory>
  /** The asker closed the app before the reply was done; Jarvis pushes it to the phone instead. */
  chatLeft(turnId: number | null, caller?: { login?: string }): Promise<void>
  /** Approves or denies one waiting request; false when Jarvis doesn't know it (answered or expired). */
  answerApproval(id: string, ok: boolean, caller?: { login?: string }): Promise<ApprovalAnswerResult>
  /** Requests still waiting for an answer, e.g. after a reload. */
  approvals(caller?: { login?: string }): Promise<Approval[]>
  /** "That was wrong" on one of his replies, with what he should have said (may be empty). */
  sendFeedback(flag: JarvisFeedback, caller?: { login?: string }): Promise<ActionResult>
  /** Stops one piece of background work and cleans up after it; gone when it had already finished. */
  stopJob(id: string, caller?: { login?: string }): Promise<ActionResult & { gone?: boolean }>
  /** Hides one offer for good (Hide on its card). */
  hideOffer(id: string, caller?: { login?: string }): Promise<ActionResult>
  /** Answers a "logged this already?" meal question: same, leftovers or new. The message is Jarvis's reply. */
  answerMeal(key: string, choice: string, caller?: { login?: string }): Promise<ActionResult>
  /** Clears notifications for every device. */
  clearNotices(which: NoticeClear, caller?: { login?: string }): Promise<ActionResult>
  /** Keeps a chat message or a notice on the list until he lets it go; the answer may carry the kept notice. */
  keepNotice(what: NoticeKeep, caller?: { login?: string }): Promise<ActionResult & { notice?: Notice }>
  /** Lets a kept one go, on every device. */
  unkeepNotice(id: string, caller?: { login?: string }): Promise<ActionResult>
  /** Passes an app's push token to Jarvis. */
  registerPush(device: PushDevice, caller?: { login?: string }): Promise<ActionResult>
  /** Night mode on a screen: tells Jarvis you've gone to bed (true) or are up (false). `from` names the screen. */
  setSleep(asleep: boolean, from: string, caller?: { login?: string }): Promise<ActionResult>
  /** What Jarvis remembers, or null when he can't be asked. */
  memory(caller?: { login?: string }): Promise<JarvisMemory | null>
  /** One day of the meal log with what he ate; '' = today. Null when Jarvis can't be asked. */
  nutritionDay(date: string, caller?: { login?: string }): Promise<NutritionDay | null>
  /** Seven days of calories against the goal, from `start`; '' = this week. Null when Jarvis can't be asked. */
  nutritionWeek(start: string, caller?: { login?: string }): Promise<NutritionWeek | null>
  /** `count` days of the meal log ending at `end` ('' = today), newest first. Null when Jarvis can't be asked. */
  nutritionDays(end: string, count: number, caller?: { login?: string }): Promise<NutritionDays | null>
  /** Nights of sleep with their score, newest first: one `night`, or the last `days`. Null when Jarvis can't be asked. */
  sleepNights(ask: { night: string; days: number }, caller?: { login?: string }): Promise<SleepNight[] | null>
  /** Stores one night of sleep (already in Jarvis's shape); `refused` when he says the night itself is wrong. */
  saveSleepNight(night: Record<string, unknown>, caller?: { login?: string }): Promise<ActionResult & { refused?: boolean; night?: SleepNight | null }>
  /** One meal's photo, or its small thumbnail when `thumb` is true. */
  mealPhoto(id: string, thumb: boolean, caller?: { login?: string }): Promise<MealPhoto>
  /** Searches past conversations (newest and best matches first). */
  searchMemory(query: string, caller?: { login?: string }): Promise<MemoryHit[]>
  /** Adds or forgets one fact. */
  changeMemory(change: MemoryChange, caller?: { login?: string }): Promise<ActionResult>
  /** Jarvis's playbooks and what their steps can use, or null when he can't be asked. */
  playbooks(caller?: { login?: string }): Promise<PlaybookBook | null>
  /** The kinds of step Jarvis last described, for checking a save. */
  stepTypes(): Promise<StepType[]>
  /** Saves, deletes or runs one playbook. */
  changePlaybook(change: PlaybookChange, caller?: { login?: string }): Promise<PlaybookResult>
  /** Has Jarvis write a playbook from a description. Nothing is saved. */
  draftPlaybook(text: string, caller?: { login?: string }): Promise<PlaybookDraftResult>
  /** One report's HTML; `gone` when it was deleted or has expired. */
  reportHtml(id: string, caller?: { login?: string }): Promise<{ html: string | null; gone: boolean }>
  /** Keeps, lets go of, or deletes one report. */
  changeReport(change: ReportChange, caller?: { login?: string }): Promise<ActionResult>
  /** How Jarvis sounds, or null when he can't be asked. */
  voice(caller?: { login?: string }): Promise<VoiceSettings | null>
  /** Saves how Jarvis sounds; used from his next reply. */
  setVoice(choice: VoiceChoice, caller?: { login?: string }): Promise<ActionResult>
  /** A short spoken sample of a voice choice. */
  voiceSample(choice: VoiceChoice, caller?: { login?: string }): Promise<VoiceSample>
  /** Starts Jarvis's web-chat engine early; true when he said yes. */
  warm(caller?: { login?: string }): Promise<boolean>
  /** Sends one command to one Home Assistant device. */
  control(entity: string, command: HomeCommand, value?: number | string, caller?: { login?: string }): Promise<ActionResult>
  /** Asks Jarvis to rewrite the digest now (calendar, email, money). */
  refreshDigest(caller?: { login?: string }): Promise<DigestRefresh>
  /** Saves, clears or re-times Money page category picks. */
  money(change: MoneyPickChange): Promise<ActionResult>
}

/** Whether Jarvis is rewriting the digest, and when it last wrote one. */
export interface DigestRefresh { running: boolean; lastWrite: string | null }

/** "That was wrong" on one of Jarvis's replies: what was asked, what he said, and what Dylan wanted. */
export interface JarvisFeedback {
  question: string
  answer: string
  note: string
}
