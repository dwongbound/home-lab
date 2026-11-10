import { useSyncExternalStore } from 'react'
import { flushSync } from 'react-dom'
import { VIEWS, type View } from './components/TopNav'

// Which page is showing, read from the URL hash (#services and so on).
// useSyncExternalStore keeps it in step with back/forward without an effect.
//
// Changing page runs inside a view transition where the browser has one
// (and motion is wanted): the browser snapshots the old page, React swaps
// in the new one synchronously, and the two crossfade. The snapshots are
// flat images, so the frosted glass stays intact the whole way through,
// which animating the panels themselves can't do.

const ids = new Set<string>(VIEWS.map((v) => v.id))
const read = (): View => { const h = window.location.hash.slice(1); return (ids.has(h) ? h : 'overview') as View }

/** True when the browser can run a view transition and motion is wanted. */
function canTransition(): boolean {
  if (typeof document.startViewTransition !== 'function') return false
  return !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

const subscribe = (cb: () => void) => {
  let shown = read()
  const onHashChange = () => {
    const next = read()
    if (next === shown) return cb()
    shown = next
    // A new page starts at the top, like any other page would.
    const swap = () => { flushSync(cb); window.scrollTo(0, 0) }
    if (canTransition()) document.startViewTransition(swap)
    else swap()
  }
  window.addEventListener('hashchange', onHashChange)
  return () => window.removeEventListener('hashchange', onHashChange)
}

/** The current page. Unknown hashes fall back to the overview. */
export function useHashView(): View {
  return useSyncExternalStore(subscribe, read, () => 'overview')
}
