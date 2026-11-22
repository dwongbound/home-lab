import { useSyncExternalStore } from 'react'

// Which report is open in the viewer, if any. Dylan asked (2026-11-18) for
// reports to open inside Jarvis rather than link somewhere else, so a tap on
// a report in the list, or on the "Open the report" link in a chat reply,
// calls openReport and the one ReportViewer on the page shows it.

/** The report on show: its id and the title to put over it. */
export interface OpenReport { id: string; title: string }

/** Report ids as Jarvis makes them (and as the server lets through). */
const REPORT_PATH = /^\/reports\/([A-Za-z0-9_-]{1,80})$/

let open: OpenReport | null = null
const listeners = new Set<() => void>()

/** Tells every subscriber the open report changed. */
function announce(): void {
  for (const listener of listeners) listener()
}

/** Shows one report in the viewer. */
export function openReport(id: string, title: string): void {
  open = { id, title }
  announce()
}

/** Closes the viewer. */
export function closeReport(): void {
  open = null
  announce()
}

/** Subscribes a component to the open report. */
function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => { listeners.delete(listener) }
}

/** The report open right now, or null. */
export function useOpenReport(): OpenReport | null {
  return useSyncExternalStore(subscribe, () => open, () => null)
}

/**
 * The report id in a link, or null when the link isn't to one of Jarvis's
 * reports. Jarvis writes the full address of this page on the tailnet, so a
 * link counts when it's on this page's own host or any ts.net host.
 */
export function reportIdFromHref(href: string, pageOrigin: string = window.location.origin): string | null {
  let url: URL
  try {
    url = new URL(href, pageOrigin)
  } catch {
    return null
  }
  const ours = url.origin === pageOrigin || url.hostname.endsWith('.ts.net')
  if (!ours) return null
  const match = url.pathname.match(REPORT_PATH)
  if (match === null) return null
  return match[1]
}
