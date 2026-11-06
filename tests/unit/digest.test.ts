// The cloud digest reader: off without a token, cached for 5 minutes, keeps
// the last good copy when GitHub fails, and asks for the raw file.
import { describe, expect, it, vi } from 'vitest'
import { createDigestReader } from '../../server/sources/digest.mjs'
import { loadConfig } from '../../server/config.mjs'

const SAMPLE = { updatedAt: '2026-11-06T10:00:00Z', threads: [], calendar: [], email: [], deploys: [], pullRequests: [] }

/** A reader with a fake clock and a fetch that answers `responses` in turn. */
function readerWith(responses: Array<Response | Error>, env: Record<string, string> = { DIGEST_TOKEN: 'read-only' }) {
  let clock = 0
  const fetch = vi.fn(async (_url: string, _init?: RequestInit) => {
    const next = responses.shift()
    if (next instanceof Error) throw next
    return next ?? new Response('', { status: 500 })
  })
  const reader = createDigestReader(loadConfig(env), { fetch, now: () => clock })
  return { reader, fetch, advance: (ms: number) => { clock += ms } }
}

describe('digest reader', () => {
  it('returns null and fetches nothing without a token', async () => {
    const { reader, fetch } = readerWith([], {})
    expect(await reader.read()).toBeNull()
    expect(fetch).not.toHaveBeenCalled()
  })

  it('asks GitHub for the raw file with the token', async () => {
    const { reader, fetch } = readerWith([Response.json(SAMPLE)])
    expect(await reader.read()).toEqual(SAMPLE)
    const [url, init] = fetch.mock.calls[0]
    expect(url).toBe('https://api.github.com/repos/dwongbound/home-lab-digest/contents/digest.json?ref=main')
    expect((init!.headers as Record<string, string>).Authorization).toBe('Bearer read-only')
    expect((init!.headers as Record<string, string>).Accept).toBe('application/vnd.github.raw+json')
  })

  it('serves from cache for 5 minutes, then fetches again', async () => {
    const { reader, fetch, advance } = readerWith([Response.json(SAMPLE), Response.json({ ...SAMPLE, updatedAt: 'later' })])
    await reader.read()
    advance(4 * 60_000)
    await reader.read()
    expect(fetch).toHaveBeenCalledTimes(1)
    advance(2 * 60_000)
    expect((await reader.read())!.updatedAt).toBe('later')
  })

  it('keeps the last good copy when GitHub fails', async () => {
    const { reader, advance } = readerWith([Response.json(SAMPLE), new Error('offline')])
    await reader.read()
    advance(6 * 60_000)
    expect(await reader.read()).toEqual(SAMPLE)
  })
})
