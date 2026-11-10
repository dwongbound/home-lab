import { useSyncExternalStore } from 'react'
import { flushSync } from 'react-dom'
import { VIEWS, type View } from './components/TopNav'

// Which page is showing, read from the URL hash (#services and so on).
// useSyncExternalStore keeps it in step with back/forward without an effect.
//
// Switching pages runs inside a view transition where the browser has one
// and motion is welcome: the browser photographs the page before and after
// and cross-fades the two pictures, while the active pill's highlight
// slides across (styles.css, "Page changes"). Animating the live page
// instead would break the glass: a transform or opacity animation on an
// ancestor of backdrop-filter shows patches until it ends.

const ids = new Set<string>(VIEWS.map((v) => v.id))
const read = (): View => { const h = window.location.hash.slice(1); return (ids.has(h) ? h : 'overview') as View }

/** True when the browser can run a view transition and the person hasn't asked for less motion. */
function canTransition(): boolean {
  if (typeof document.startViewTransition !== 'function') return false
  return !window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** Tells React the hash changed, inside a view transition when one is welcome. */
function subscribe(notify: () => void) {
  const onHashChange = () => {
    if (!canTransition()) {
      notify()
      return
    }
    // flushSync makes React draw the new page before the browser takes the
    // "after" picture; without it the picture would still show the old page.
    document.startViewTransition(() => flushSync(notify))
  }
  window.addEventListener('hashchange', onHashChange)
  return () => window.removeEventListener('hashchange', onHashChange)
}

/** The current page. Unknown hashes fall back to the overview. */
export function useHashView(): View {
  return useSyncExternalStore(subscribe, read, () => 'overview')
}
