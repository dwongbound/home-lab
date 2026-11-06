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
