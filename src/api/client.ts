// The page's only door to data. Components call useSnapshot(), runAction(),
// askJarvis(), controlDevice(), refreshDigest() and changeMoneyPicks(); nothing else in src/ knows where the
// numbers come from.
//
// Normally both go to the small Node server on the PC (server/app.mjs).
// A build made with VITE_DATA=static has no server (that's the shareable
// preview), so it runs the mock source inside the browser instead.
import useSWR from 'swr'
import type { ActionName, ActionResult, DataSource, DigestRefresh, HomeCommand, MoneyPickChange, Snapshot } from '../types'

export const SNAPSHOT_KEY = '/api/snapshot'
const REFRESH_MS = 15_000
const IS_STATIC_BUILD = import.meta.env.VITE_DATA === 'static'

let staticSource: Promise<DataSource> | null = null

/**
 * Loads the in-browser mock source, once. It's a dynamic import so the
 * normal build never ships the mock data (Vercel rule bundle-conditional).
 */
function getStaticSource(): Promise<DataSource> {
  if (staticSource === null) {
    // The .mjs file is untyped JavaScript; its shape is checked by the
    // server tests against the same Snapshot type.
    staticSource = import('../../server/sources/mock.mjs').then((m) => m.createMockSource() as unknown as DataSource)
  }
  return staticSource
}

/** Fetches one snapshot of the PC. Throws with a readable message on failure. */
async function fetchSnapshot(): Promise<Snapshot> {
  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    return source.snapshot()
  }
  const res = await fetch(SNAPSHOT_KEY, { headers: { accept: 'application/json' } })
  if (!res.ok) {
    throw new Error(`The server answered ${res.status}`)
  }
  return res.json()
}

/**
 * The snapshot, refreshed every 15 seconds and when the tab regains focus.
 * SWR shares one request between every component that calls this
 * (Vercel rule client-swr-dedup).
 */
export function useSnapshot() {
  return useSWR<Snapshot>(SNAPSHOT_KEY, fetchSnapshot, {
    refreshInterval: REFRESH_MS,
    revalidateOnFocus: true,
    keepPreviousData: true,
  })
}

/**
 * Runs a server action (load or unload Gemma). The caller refetches the
 * snapshot afterwards, through its own SWR cache.
 */
export async function runAction(name: ActionName): Promise<ActionResult> {
  let result: ActionResult

  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    result = await source.action(name)
  } else {
    // The custom header is a cheap guard: a plain cross-site form post
    // can't set it, so another web page can't trigger actions.
    const res = await fetch(`/api/actions/${name}`, { method: 'POST', headers: { 'x-home-lab': '1' } })
    try {
      result = await res.json()
    } catch {
      result = { ok: false, message: `The server answered ${res.status}` }
    }
  }
  return result
}

/** Asks Jarvis a question. On success `message` is the reply. */
export async function askJarvis(text: string): Promise<ActionResult> {
  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    return source.ask(text)
  }
  const res = await fetch('/api/jarvis/ask', {
    method: 'POST',
    headers: { 'x-home-lab': '1', 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
  })
  try {
    return await res.json()
  } catch {
    return { ok: false, message: `The server answered ${res.status}` }
  }
}

/** Sends one command to one Home Assistant device. */
export async function controlDevice(entity: string, command: HomeCommand, value?: number | string): Promise<ActionResult> {
  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    return source.control(entity, command, value)
  }
  const res = await fetch('/api/home/control', {
    method: 'POST',
    headers: { 'x-home-lab': '1', 'content-type': 'application/json' },
    body: JSON.stringify({ entity, command, value }),
  })
  try {
    return await res.json()
  } catch {
    return { ok: false, message: `The server answered ${res.status}` }
  }
}

/** Asks Jarvis to rewrite the digest now. Never throws: trouble reads as "not running". */
export async function refreshDigest(): Promise<DigestRefresh> {
  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    return source.refreshDigest()
  }
  try {
    const res = await fetch('/api/digest/refresh', { method: 'POST', headers: { 'x-home-lab': '1' } })
    if (!res.ok) return { running: false, lastWrite: null }
    return await res.json()
  } catch {
    return { running: false, lastWrite: null }
  }
}

/** Saves, clears or re-times a Money page category pick. */
export async function changeMoneyPicks(change: MoneyPickChange): Promise<ActionResult> {
  if (IS_STATIC_BUILD) {
    const source = await getStaticSource()
    return source.money(change)
  }
  try {
    const res = await fetch('/api/money/picks', {
      method: 'POST',
      headers: { 'x-home-lab': '1', 'content-type': 'application/json' },
      body: JSON.stringify(change),
    })
    return await res.json()
  } catch {
    return { ok: false, message: 'The server is not answering' }
  }
}
