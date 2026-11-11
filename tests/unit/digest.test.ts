// The cloud digest reader: off without a token, cached for 2 minutes, keeps
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

  it('serves from cache for 2 minutes, then fetches again', async () => {
    const { reader, fetch, advance } = readerWith([Response.json(SAMPLE), Response.json({ ...SAMPLE, updatedAt: 'later' })])
    await reader.read()
    advance(90_000)
    await reader.read()
    expect(fetch).toHaveBeenCalledTimes(1)
    advance(60_000)
    expect((await reader.read())!.updatedAt).toBe('later')
  })

  it('keeps the last good copy when GitHub fails', async () => {
    const { reader, advance } = readerWith([Response.json(SAMPLE), new Error('offline')])
    await reader.read()
    advance(6 * 60_000)
    expect(await reader.read()).toEqual(SAMPLE)
  })

  it('reads a local file instead when DIGEST_FILE is set, with no token', async () => {
    const readFile = vi.fn(async () => JSON.stringify(SAMPLE))
    const fetch = vi.fn()
    const reader = createDigestReader(loadConfig({ DIGEST_FILE: '/data/digest.json' }), { fetch, readFile, now: () => 0 })
    expect(await reader.read()).toEqual(SAMPLE)
    expect(readFile).toHaveBeenCalledWith('/data/digest.json', 'utf8')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('takes the threads from THREADS_FILE when it reads, and keeps the digest without it', async () => {
    const threads = [{ id: 't1', title: 'Home Lab Page', state: 'working', lastActivityAt: '2026-11-11T00:33:38Z', url: 'https://claude.ai/x' }]
    const files: Record<string, string> = {
      '/digest/digest.json': JSON.stringify({ ...SAMPLE, threads: [] }),
      '/digest/threads.json': JSON.stringify({ updatedAt: '2026-11-11T00:40:00Z', threads }),
    }
    const readFile = vi.fn(async (path: string) => {
      if (!(path in files)) throw new Error('ENOENT')
      return files[path]
    })
    const config = loadConfig({ DIGEST_FILE: '/digest/digest.json', THREADS_FILE: '/digest/threads.json' })
    const digest: any = await createDigestReader(config, { readFile, now: () => 0 }).read()
    expect(digest.threads).toEqual(threads)
    // No threads file yet, or a broken one: the digest's own threads stay.
    delete files['/digest/threads.json']
    const without: any = await createDigestReader(config, { readFile, now: () => 0 }).read()
    expect(without.threads).toEqual([])
    files['/digest/threads.json'] = '{"threads":'
    const broken: any = await createDigestReader(config, { readFile, now: () => 0 }).read()
    expect(broken.threads).toEqual([])
  })

  it('drops events from skipped calendars (Wong Fam by default)', async () => {
    const event = (calendar: string) => ({ id: calendar, title: 'x', start: '', end: '', allDay: false, calendar })
    const digest = { ...SAMPLE, calendar: [event('Personal'), event('Wong Fam'), event('wong fam')] }
    const { reader } = readerWith([Response.json(digest)])
    expect((await reader.read()).calendar.map((e: { calendar: string }) => e.calendar)).toEqual(['Personal'])
  })
})
