import { createContext, useContext, useEffect, useRef, useState } from 'react'
import { refreshDigest } from './client'

// Opening the page (or coming back to it) asks Jarvis to rewrite the digest,
// so calendar, email and money are fresh. The page keeps showing the last
// digest meanwhile, with "Updating from Jarvis…" on its panels, and checks
// for the new one every few seconds until it lands.

// Don't ask again within this long of the last ask (Jarvis also skips a
// run when its last write is under 2 minutes old).
const ASK_GAP_MS = 2 * 60_000
// When Jarvis doesn't say when it last wrote: the PC's clock and the
// phone's can differ a little, so a digest written this close before the
// ask counts as the new one.
const CLOCK_SLACK_MS = 10_000
// How often to look for the new digest while Jarvis works.
const CHECK_MS = 5_000
// Give up waiting after this long; the 15-minute job still runs.
const GIVE_UP_MS = 3 * 60_000

/** True while Jarvis is rewriting the digest. Read by the cloud panels. */
export const DigestRefreshing = createContext(false)

/** Whether Jarvis is rewriting the digest right now. */
export function useDigestRefreshing(): boolean {
  return useContext(DigestRefreshing)
}

/**
 * Asks for a refresh on load and when the tab comes back, and reports
 * whether one is running. `updatedAt` is the digest's stamp: once it's
 * later than Jarvis's last write before this run (or, if Jarvis didn't
 * say, about the time of the ask), the new digest has arrived. It isn't
 * compared with the stamp on screen because the first ask can go out
 * before the first snapshot. `recheck` refetches the snapshot.
 */
export function useDigestRefresh(updatedAt: string | null, recheck: () => void): boolean {
  // A digest stamped after this (ms) is the new one; null when not waiting.
  const [newerThan, setNewerThan] = useState<number | null>(null)
  const lastAsk = useRef(0)

  // Ask on load, and on focus once the gap has passed.
  useEffect(() => {
    let alive = true
    /** Asks Jarvis, unless we asked recently. */
    async function ask() {
      if (Date.now() - lastAsk.current < ASK_GAP_MS) return
      const at = Date.now()
      lastAsk.current = at
      const answer = await refreshDigest()
      if (!alive || !answer.running) return
      let since = at - CLOCK_SLACK_MS
      if (answer.lastWrite !== null) since = Date.parse(answer.lastWrite) + 1
      setNewerThan(since)
    }
    /** Only when the page is actually visible again. */
    function onVisible() {
      if (document.visibilityState === 'visible') void ask()
    }
    void ask()
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('focus', onVisible)
    return () => {
      alive = false
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('focus', onVisible)
    }
  }, [])

  const waiting = newerThan !== null

  // The new digest is here: stop waiting.
  useEffect(() => {
    if (newerThan === null || updatedAt === null) return
    if (Date.parse(updatedAt) >= newerThan) setNewerThan(null)
  }, [newerThan, updatedAt])

  // While waiting, look every few seconds, and give up after a while.
  useEffect(() => {
    if (!waiting) return
    const check = setInterval(recheck, CHECK_MS)
    const stop = setTimeout(() => setNewerThan(null), GIVE_UP_MS)
    return () => { clearInterval(check); clearTimeout(stop) }
  }, [waiting, recheck])

  return waiting
}
