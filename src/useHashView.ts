import { useSyncExternalStore } from 'react'
import { VIEWS, type View } from './components/TopNav'

// Which page is showing, read from the URL hash (#services and so on).
// useSyncExternalStore keeps it in step with back/forward without an effect.

const ids = new Set<string>(VIEWS.map((v) => v.id))
const subscribe = (cb: () => void) => { window.addEventListener('hashchange', cb); return () => window.removeEventListener('hashchange', cb) }
const read = (): View => { const h = window.location.hash.slice(1); return (ids.has(h) ? h : 'overview') as View }

/** The current page. Unknown hashes fall back to the overview. */
export function useHashView(): View {
  return useSyncExternalStore(subscribe, read, () => 'overview')
}
