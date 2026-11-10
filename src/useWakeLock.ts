import { useEffect, useState } from 'react'

// Keeps the screen on while the page is showing, for an iPad left up as a
// wall display. Uses the Screen Wake Lock API (Safari 16.4+, Chrome). The
// browser drops the lock whenever the tab is hidden, so it's asked for
// again each time the page comes back.

export type WakeState = 'off' | 'on' | 'unsupported'

/** Whether this browser has the Screen Wake Lock API. */
export function wakeLockSupported(): boolean {
  return typeof navigator !== 'undefined' && 'wakeLock' in navigator
}

/** Holds a screen wake lock while `wanted` is true. Returns whether it's held. */
export function useWakeLock(wanted: boolean): WakeState {
  const [state, setState] = useState<WakeState>('off')

  useEffect(() => {
    if (!wanted) { setState('off'); return }
    if (!wakeLockSupported()) { setState('unsupported'); return }
    let lock: WakeLockSentinel | null = null
    let stopped = false

    /** Asks for the lock; a refusal (low battery, not visible) just leaves it off. */
    const acquire = async () => {
      if (document.visibilityState !== 'visible' || lock !== null) return
      try {
        const got = await navigator.wakeLock.request('screen')
        if (stopped) { void got.release(); return }
        lock = got
        setState('on')
        got.addEventListener('release', () => { lock = null; if (!stopped) setState('off') })
      } catch {
        setState('off')
      }
    }

    void acquire()
    const onVisible = () => { void acquire() }
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      stopped = true
      document.removeEventListener('visibilitychange', onVisible)
      void lock?.release()
    }
  }, [wanted])

  return state
}
