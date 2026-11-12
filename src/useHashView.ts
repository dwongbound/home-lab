import { useSyncExternalStore } from 'react'
import { flushSync } from 'react-dom'
import { VIEWS, type View } from './components/TopNav'
import { clearSwipe, motionWanted } from './swipeMotion'

// Which page is showing, read from the URL hash (#services and so on), and
// which detail is open on it (#money/t/x1: transaction x1 on Money). Details
// live in the hash so every row is a plain link, can be shared or
// bookmarked, and Back closes the pop-up.
// useSyncExternalStore keeps both in step with back/forward without an effect.
//
// Changing page swaps it at once. A tap on a pill fades the new page in
// (the title here, the panels' contents in useReveal), the same soft fade
// the first load uses (Dylan, 2026-11-12). A swipe slides it in from the
// side the finger went, carrying on from the swipe. There are no view
// transitions: WebKit's snapshots dropped the glass, and one fade
// everywhere is simpler.

const ids = new Set<string>(VIEWS.map((v) => v.id))

/** The hash split into the page and the rest ("money/t/x1" → ["money", "t/x1"]). */
function hashParts(): [string, string] {
  const h = window.location.hash.slice(1)
  const slash = h.indexOf('/')
  if (slash < 0) return [h, '']
  return [h.slice(0, slash), h.slice(slash + 1)]
}

const read = (): View => { const page = hashParts()[0]; return (ids.has(page) ? page : 'overview') as View }

// How long the title's enter animation runs (matches styles.css), after
// which the marker comes off so it can play again.
const ENTER_MS = 1100
let enterTimer: ReturnType<typeof setTimeout> | undefined

/**
 * Marks the page change on <html> for styles.css: "fade" after a tap (the
 * title fades in), "next"/"prev" after a swipe (title and panels slide in,
 * translate only, from that side). The glass itself never fades.
 */
function playEnter(kind: 'next' | 'prev' | 'fade'): void {
  // A swipe's glide-out ends here, in the same frame the new page comes in.
  clearSwipe()
  if (!motionWanted()) return
  const root = document.documentElement
  // Remove and re-add, so a quick second change restarts the animation.
  delete root.dataset.enter
  void root.offsetWidth
  root.dataset.enter = kind
  clearTimeout(enterTimer)
  enterTimer = setTimeout(() => { delete root.dataset.enter }, ENTER_MS)
}

/** Which way a page change goes, by the pills' order: to the right is "next". */
function directionOf(from: View, to: View): 'next' | 'prev' {
  const order = VIEWS.map((v) => v.id as View)
  return order.indexOf(to) >= order.indexOf(from) ? 'next' : 'prev'
}

// Set by swipeToView: the next page change slides the way the finger went
// rather than fading, so it carries on from the swipe.
let swiping = false

const subscribe = (cb: () => void) => {
  let shown = read()
  const onHashChange = () => {
    const next = read()
    if (next === shown) return cb()
    const direction = directionOf(shown, next)
    shown = next
    // A new page starts at the top, like any other page would.
    const swap = () => { flushSync(cb); window.scrollTo(0, 0) }
    const swiped = swiping
    swiping = false
    // Marked first, so the new panels' fades start with the shorter page-change delay.
    playEnter(swiped ? direction : 'fade')
    swap()
  }
  window.addEventListener('hashchange', onHashChange)
  return () => window.removeEventListener('hashchange', onHashChange)
}

/** Goes to another page after a swipe: the new page slides in from the side. */
export function swipeToView(view: View): void {
  swiping = true
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
