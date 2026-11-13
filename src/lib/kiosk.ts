import type { View } from '../components/TopNav'

// Kiosk mode: the page full screen on the iPad as a wall display, moving
// through the tabs by itself (Dylan, 2026-11-13). These are the plain
// pieces; src/useKiosk.ts runs the timer.

/** The tabs kiosk mode shows, in order. Settings is left out. */
export const KIOSK_VIEWS: View[] = ['overview', 'home', 'claude', 'money', 'services', 'schedule']

/** How long each tab stays up. */
export const KIOSK_DWELL_MS = 20_000

/** After a touch, a key or a scroll, how long the cycling waits before carrying on. */
export const KIOSK_IDLE_MS = 60_000

/** The tab after `view`, wrapping from the last back to the first. A tab not in the cycle starts it over. */
export function nextKioskView(view: View): View {
  const i = KIOSK_VIEWS.indexOf(view)
  if (i < 0 || i === KIOSK_VIEWS.length - 1) return KIOSK_VIEWS[0]
  return KIOSK_VIEWS[i + 1]
}

/**
 * When the next tab is due: a full dwell after this one appeared, and a
 * full idle wait after he last touched the page, whichever is later.
 */
export function kioskDueAt(shownAt: number, touchedAt: number): number {
  return Math.max(shownAt + KIOSK_DWELL_MS, touchedAt + KIOSK_IDLE_MS)
}

// Safari before 16.4 (and iPadOS's) only has the webkit-prefixed fullscreen calls.
type WebkitDocument = Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => Promise<void> | void }
type WebkitElement = HTMLElement & { webkitRequestFullscreen?: () => Promise<void> | void }

/** Whether the page is showing full screen right now. */
export function isFullscreen(): boolean {
  const d = document as WebkitDocument
  return Boolean(d.fullscreenElement ?? d.webkitFullscreenElement)
}

/**
 * Asks for full screen. Not every browser can (iPhone Safari can't, and a
 * Home Screen web app already is), so a refusal just leaves the page as it
 * is: kiosk mode still cycles. Resolves to whether it went full screen.
 */
export async function enterFullscreen(): Promise<boolean> {
  const el = document.documentElement as WebkitElement
  try {
    if (typeof el.requestFullscreen === 'function') await el.requestFullscreen()
    else if (typeof el.webkitRequestFullscreen === 'function') await el.webkitRequestFullscreen()
    else return false
  } catch {
    return false
  }
  return isFullscreen()
}

/** Leaves full screen, if the page is in it. */
export function exitFullscreen(): void {
  if (!isFullscreen()) return
  const d = document as WebkitDocument
  try {
    if (typeof d.exitFullscreen === 'function') void d.exitFullscreen().catch(() => undefined)
    else if (typeof d.webkitExitFullscreen === 'function') void d.webkitExitFullscreen()
  } catch { /* already out */ }
}
