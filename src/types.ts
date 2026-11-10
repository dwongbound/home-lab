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

export interface CloudDigest {
  updatedAt: string
  threads: ClaudeThread[]
  calendar: CalendarEvent[]
  email: EmailItem[]
  deploys: Deploy[]
  pullRequests: PullRequest[]
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
