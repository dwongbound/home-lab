// One small per-browser preference. Storage can be missing or blocked, so
// every access is guarded (js-cache-storage, client-localstorage-schema).
const KEY = 'home-lab:v1:sky'
const OK = new Set(['auto', 'dawn', 'day', 'dusk', 'night'])

/** The saved sky choice, or "auto" if nothing valid is saved. */
export function readSky(): string {
  try { const v = localStorage.getItem(KEY); return v && OK.has(v) ? v : 'auto' } catch { return 'auto' }
}
/** Saves the sky choice. Silently does nothing if storage is blocked. */
export function writeSky(v: string): void {
  try { localStorage.setItem(KEY, v) } catch { /* not saved; fine */ }
}

const AWAKE_KEY = 'home-lab:v1:awake'

/** Whether this browser should keep its screen on (the iPad as a wall display). Off unless saved on. */
export function readAwake(): boolean {
  try { return localStorage.getItem(AWAKE_KEY) === 'on' } catch { return false }
}
/** Saves the keep-awake choice. Silently does nothing if storage is blocked. */
export function writeAwake(on: boolean): void {
  try { localStorage.setItem(AWAKE_KEY, on ? 'on' : 'off') } catch { /* not saved; fine */ }
}
