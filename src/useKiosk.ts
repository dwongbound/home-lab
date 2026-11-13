import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import type { View } from './components/TopNav'
import { enterFullscreen, exitFullscreen, isFullscreen, KIOSK_VIEWS, kioskDueAt, nextKioskView } from './lib/kiosk'
import { readKiosk, writeKiosk } from './lib/prefs'

// Kiosk mode (Dylan, 2026-11-13): the button top right puts the page full
// screen and moves through Overview, Home, Claude, Money, Services and
// Schedule by itself, for the iPad as an always-on display. Close leaves it.
//
// It pauses while he's using the page: a touch, key or scroll waits a
// minute before carrying on, and nothing moves while a pop-up or the chat
// is open (useScrollLock marks those on <html> as data-modal). It's
// remembered, so a reload after a deploy keeps cycling; full screen itself
// can't come back without a tap, but the cycling does.

/** Whether the page is in kiosk mode, for views that show less there (Money). */
export const KioskMode = createContext(false)

/** True inside kiosk mode. */
export function useInKiosk(): boolean {
  return useContext(KioskMode)
}

/** Whether a pop-up is open, or the hash names a detail (#money/t/x1). */
function somethingOpen(): boolean {
  if (document.documentElement.dataset.modal !== undefined) return true
  return window.location.hash.includes('/')
}

/** Runs kiosk mode for the page showing `view`. */
export function useKiosk(view: View) {
  const [on, setOn] = useState(readKiosk)
  // Whether kiosk mode put the page full screen, so leaving full screen (Esc, the browser's own control) also leaves kiosk mode.
  const wentFull = useRef(false)
  // When he last touched the page; the cycling waits a while after.
  const touchedAt = useRef(0)
  const viewRef = useRef(view)
  viewRef.current = view

  /** Turns kiosk mode on. Called from the button's tap, which is what lets the browser go full screen. */
  const start = useCallback(() => {
    setOn(true)
    writeKiosk(true)
    touchedAt.current = 0
    void enterFullscreen().then((ok) => { wentFull.current = ok })
    // Settings isn't in the cycle, so start from the Overview.
    if (!KIOSK_VIEWS.includes(viewRef.current)) window.location.hash = 'overview'
  }, [])

  /** Turns kiosk mode off and leaves full screen. */
  const stop = useCallback(() => {
    setOn(false)
    writeKiosk(false)
    wentFull.current = false
    exitFullscreen()
  }, [])

  // Leaving full screen some other way ends kiosk mode too.
  useEffect(() => {
    if (!on) return
    const onChange = () => { if (wentFull.current && !isFullscreen()) stop() }
    document.addEventListener('fullscreenchange', onChange)
    document.addEventListener('webkitfullscreenchange', onChange)
    return () => {
      document.removeEventListener('fullscreenchange', onChange)
      document.removeEventListener('webkitfullscreenchange', onChange)
    }
  }, [on, stop])

  // Any touch, key or scroll counts as him using the page. Not 'scroll':
  // the page scrolls itself to the top on every tab change.
  useEffect(() => {
    if (!on) return
    const touched = () => { touchedAt.current = Date.now() }
    const events = ['pointerdown', 'keydown', 'wheel', 'touchstart'] as const
    for (const e of events) window.addEventListener(e, touched, { passive: true })
    return () => { for (const e of events) window.removeEventListener(e, touched) }
  }, [on])

  // The cycle: a check every second, so a pause or a pop-up closing is
  // picked up without juggling timers. Restarts with each new tab, which
  // is when that tab's dwell starts.
  useEffect(() => {
    if (!on) return
    const shownAt = Date.now()
    const id = setInterval(() => {
      if (document.visibilityState !== 'visible') return
      // A pop-up counts as in use, so closing it waits the full minute too.
      if (somethingOpen()) { touchedAt.current = Date.now(); return }
      if (Date.now() < kioskDueAt(shownAt, touchedAt.current)) return
      window.location.hash = nextKioskView(view)
    }, 1000)
    return () => clearInterval(id)
  }, [on, view])

  return { on, start, stop }
}
