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
}

export interface ActionResult { ok: boolean; message: string }
export type ActionName = 'ollama-unload' | 'ollama-load'

/** What both server sources (mock and live) look like from the outside. */
export interface DataSource {
  kind: 'mock' | 'live'
  snapshot(): Promise<Snapshot>
  action(name: ActionName): Promise<ActionResult>
}
