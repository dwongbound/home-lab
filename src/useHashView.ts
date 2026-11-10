import { useSyncExternalStore } from 'react'
import { flushSync } from 'react-dom'
import { VIEWS, type View } from './components/TopNav'

// Which page is showing, read from the URL hash (#services and so on), and
// which detail is open on it (#money/t/x1: transaction x1 on Money). Details
// live in the hash so every row is a plain link, can be shared or
// bookmarked, and Back closes the pop-up.
// useSyncExternalStore keeps both in step with back/forward without an effect.
//
// Changing page runs inside a view transition where the browser has one
// (and motion is wanted): the browser snapshots the old page, React swaps
// in the new one synchronously, and the two crossfade. The snapshots are
// flat images, so the frosted glass stays intact the whole way through,
// which animating the panels themselves can't do.

const ids = new Set<string>(VIEWS.map((v) => v.id))

/** The hash split into the page and the rest ("money/t/x1" → ["money", "t/x1"]). */
function hashParts(): [string, string] {
  const h = window.location.hash.slice(1)
  const slash = h.indexOf('/')
  if (slash < 0) return [h, '']
  return [h.slice(0, slash), h.slice(slash + 1)]
}

const read = (): View => { const page = hashParts()[0]; return (ids.has(page) ? page : 'overview') as View }

/** True when motion is wanted (no reduce-motion setting). */
function motionWanted(): boolean {
  return !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
}

/**
 * True in Safari and every other WebKit browser (all of them on iPad and
 * iPhone). WebKit's view-transition snapshots leave out backdrop-filter, so
 * the crossfaded panels show dark, untinted glass and then "pop" frosted
 * when the live page returns. There's no feature test for that, so it's
 * read from the user agent: WebKit without Chrome's or Firefox's own engine.
 */
function snapshotsDropGlass(): boolean {
  const ua = navigator.userAgent
  return /AppleWebKit/.test(ua) && !/Chrome|Chromium|Edg\/|Android/.test(ua)
}

/** True when the browser can run a view transition that keeps the glass. */
function canTransition(): boolean {
  if (typeof document.startViewTransition !== 'function') return false
  if (snapshotsDropGlass()) return false
  return motionWanted()
}

// How long the contents take to slide in where there's no view transition
// (matches the enter animation in styles.css).
const ENTER_MS = 420
let enterTimer: ReturnType<typeof setTimeout> | undefined

/**
 * Without a view transition (WebKit), the page swaps at once and only the
 * contents of each panel slide in, from the side the new page came from.
 * The glass itself never fades or moves, so it stays frosted throughout.
 */
function playEnter(direction: 'next' | 'prev'): void {
  if (!motionWanted()) return
  const root = document.documentElement
  // Remove and re-add, so a quick second change restarts the animation.
  delete root.dataset.enter
  void root.offsetWidth
  root.dataset.enter = direction
  clearTimeout(enterTimer)
  enterTimer = setTimeout(() => { delete root.dataset.enter }, ENTER_MS)
}

/** Which way a page change goes, by the pills' order: to the right is "next". */
function directionOf(from: View, to: View): 'next' | 'prev' {
  const order = VIEWS.map((v) => v.id as View)
  return order.indexOf(to) >= order.indexOf(from) ? 'next' : 'prev'
}

const subscribe = (cb: () => void) => {
  let shown = read()
  const onHashChange = () => {
    const next = read()
    if (next === shown) return cb()
    const direction = directionOf(shown, next)
    shown = next
    // A new page starts at the top, like any other page would.
    const swap = () => { flushSync(cb); window.scrollTo(0, 0) }
    if (canTransition()) {
      document.startViewTransition(swap)
      return
    }
    swap()
    playEnter(direction)
  }
  window.addEventListener('hashchange', onHashChange)
  return () => window.removeEventListener('hashchange', onHashChange)
}

/** Goes to another page (a swipe does this), the same as tapping its pill. */
export function goToView(view: View): void {
  window.location.hash = view
}

/** The current page. Unknown hashes fall back to the overview. */
export function useHashView(): View {
  return useSyncExternalStore(subscribe, read, () => 'overview')
}

/** What's open on the page: "t/x1", or "" when nothing is. */
const readDetail = (): string => hashParts()[1]

/** Tells React when the hash changes, for the detail part. */
const subscribeDetail = (cb: () => void) => {
  window.addEventListener('hashchange', cb)
  return () => window.removeEventListener('hashchange', cb)
}

/** The open detail ("t/x1"), or "" when none is. */
export function useHashDetail(): string {
  return useSyncExternalStore(subscribeDetail, readDetail, () => '')
}

/** A link to one detail on a page: detailHref('money', 't', 'x1') → "#money/t/x1". */
export function detailHref(view: View, kind: string, id = ''): string {
  if (!id) return `#${view}/${kind}`
  return `#${view}/${kind}/${encodeURIComponent(id)}`
}

/** A detail string split into its kind and id ("t/x1" → { kind: "t", id: "x1" }). */
export function parseDetail(detail: string): { kind: string; id: string } {
  const slash = detail.indexOf('/')
  if (slash < 0) return { kind: detail, id: '' }
  let id = detail.slice(slash + 1)
  try { id = decodeURIComponent(id) } catch { /* a hand-typed bad escape: use it as it is */ }
  return { kind: detail.slice(0, slash), id }
}

/**
 * Closes whatever detail is open, staying on the page. It replaces the
 * history entry rather than adding one, so Back afterwards doesn't reopen
 * the pop-up. replaceState fires no hashchange, so it sends one itself.
 */
export function closeDetail(): void {
  const page = hashParts()[0] || 'overview'
  window.history.replaceState(window.history.state, '', `#${page}`)
  window.dispatchEvent(new HashChangeEvent('hashchange'))
}
