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
  /** Thermostats only: the lowest and highest target, and how far one press moves it. */
  min?: number
  max?: number
  step?: number
  /** Thermostats only: the modes it offers ("off", "heat", "cool", "heat_cool"...). */
  modes?: string[]
}
export interface HomeState {
  devices: Device[]
  weather: { condition: string; temperature: number | null; unit: string } | null
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
  /** null until the digest is set up (no token) or before its first read. */
  cloud: CloudDigest | null
  /** null without a Home Assistant token, or when it doesn't answer. */
  home: HomeState | null
  /** What Jarvis runs in the background (GET /jobs); null on an older Jarvis or when it doesn't answer. */
  jobs: JarvisJobs | null
  /** Money page category picks waiting to be applied in Copilot. */
  moneyPicks: MoneyPicks
}

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

/** One piece of Jarvis's streamed chat reply: more words, the end, or what went wrong. */
/**
 * Jarvis asking before he writes a file or runs a command on the PC. He
 * waits (up to `expires`) for Approve or Deny from the page, a spoken yes
 * or no in Talk, or Telegram, whichever answers first.
 */
export interface Approval { id: string; tool: string; summary: string; expires: string }
/** Who settled an approval: a tap on the page, a spoken yes or no in Talk, Telegram, or nobody in time. */
export type ApprovalBy = 'page' | 'voice' | 'telegram' | 'timeout'
export type ChatEvent =
  | { type: 'delta'; text: string }
  | { type: 'done'; ok: true }
  | { type: 'error'; message: string }
  | { type: 'approval'; approval: Approval }
  | { type: 'approval_done'; id: string; ok: boolean; by: ApprovalBy }
/** One saved line of the web chat. */
export interface ChatTurn { role: 'user' | 'jarvis'; text: string; at: string }
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
  chat(text: string, caller: { login?: string }, onEvent: (event: ChatEvent) => void): Promise<void>
  /** The web chat with Jarvis so far, oldest first. */
  history(caller?: { login?: string }): Promise<ChatTurn[]>
  /** Approves or denies one waiting request; false when Jarvis doesn't know it (answered or expired). */
  answerApproval(id: string, ok: boolean, caller?: { login?: string }): Promise<ActionResult>
  /** Requests still waiting for an answer, e.g. after a reload. */
  approvals(caller?: { login?: string }): Promise<Approval[]>
  /** What Jarvis remembers, or null when he can't be asked. */
  memory(caller?: { login?: string }): Promise<JarvisMemory | null>
  /** Searches past conversations (newest and best matches first). */
  searchMemory(query: string, caller?: { login?: string }): Promise<MemoryHit[]>
  /** Adds or forgets one fact. */
  changeMemory(change: MemoryChange, caller?: { login?: string }): Promise<ActionResult>
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
