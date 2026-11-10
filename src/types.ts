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
export interface TimelineItem { id: string; at: string; title: string; detail: string; status: RunStatus }
export interface ActivityItem { id: string; at: string; kind: 'jarvis' | 'ha' | 'ollama' | 'system'; text: string }
export interface Service { id: string; name: string; detail: string; status: ServiceStatus; latencyMs?: number; url?: string }

// The cloud digest: what a scheduled Claude task collects from claude.ai
// (project threads) and Dylan's connectors, written to a private repo and
// read by the PC. See docs/digest.md for how it's made.
export type ThreadState = 'working' | 'blocked' | 'review_ready' | 'done' | 'failed' | 'stopped'
export interface ClaudeThread { id: string; title: string; state: ThreadState; lastActivityAt: string; url: string }
export interface CalendarEvent { id: string; title: string; start: string; end: string; allDay: boolean; calendar: string }
export interface EmailItem { id: string; from: string; subject: string; why: string }
export interface Deploy { project: string; state: 'ready' | 'building' | 'error'; at: string; url: string }
export interface PullRequest { repo: string; number: number; title: string; ci: 'passing' | 'failing' | 'running' | 'none'; url: string }

// Money, from Dylan's Copilot connector by way of the digest. Amounts are
// US dollars. A balance is what the account holds, except for credit and
// loan accounts, where it's what's owed (positive either way).
export type AccountKind = 'cash' | 'credit' | 'investment' | 'loan' | 'other'
export interface MoneyAccount { id: string; name: string; institution: string; kind: AccountKind; balance: number }
export interface SpendCategory { name: string; spent: number; budget: number | null }
export interface MoneyTransaction { id: string; date: string; merchant: string; category: string; amount: number }
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

export interface Snapshot {
  generatedAt: string
  source: 'mock' | 'live'
  host: { name: string; os: string; uptimeSec: number }
  metrics: Metric[]
  requests: DayCount[]
  today: TimelineItem[]
  activity: ActivityItem[]
  services: Service[]
  model: { name: string; loaded: boolean; vramGb: number; loadSeconds: number | null }
  /** null until the digest is set up (no token) or before its first read. */
  cloud: CloudDigest | null
}

export interface ActionResult { ok: boolean; message: string }
export type ActionName = 'ollama-unload' | 'ollama-load'

/** What both server sources (mock and live) look like from the outside. */
export interface DataSource {
  kind: 'mock' | 'live'
  snapshot(): Promise<Snapshot>
  action(name: ActionName): Promise<ActionResult>
  /** Asks Jarvis. On success `message` is Jarvis's reply. */
  ask(text: string, caller?: { login?: string }): Promise<ActionResult>
}
