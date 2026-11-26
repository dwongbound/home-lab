// Reports: Jarvis's list cleaned for the apps, the locked-down page a report is served as, and Keep/Delete.
import { describe, expect, it, vi } from 'vitest'
import { createApi } from '../../server/app.mjs'
import { loadConfig } from '../../server/config.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { REPORT_CSP, isReportId, parseReports } from '../../server/sources/reports.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }
const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })
/** The fields these tests read from a report row. */
type JarvisReport = { id: string; keepDays: number | null }

describe('parseReports', () => {
  it('maps Jarvis’s snake_case list and drops rows that aren’t reports', () => {
    const parsed = parseReports({
      reports: [
        { id: 'ab12', title: ' Speakers ', summary: 'Five pairs', created: '2026-11-18T20:00:00Z', expires: '2026-12-18T20:00:00Z', kept: false, bytes: 184000 },
        { id: 'cd34', title: 'Week', created: '2026-11-12T20:00:00Z', expires: '2026-12-12T20:00:00Z', kept: true, bytes: 1 },
        { id: '../etc', title: 'Bad id', created: '2026-11-12T20:00:00Z' },
        { id: 'ef56', title: '', created: '2026-11-12T20:00:00Z' },
        { id: 'gh78', title: 'No date' },
      ],
      total_bytes: 184001,
      keep_days: 30,
      max_bytes: 200000000,
    })
    expect(parsed?.reports.map((r: JarvisReport) => r.id)).toEqual(['ab12', 'cd34'])
    expect(parsed?.reports[0]).toEqual({ id: 'ab12', title: 'Speakers', summary: 'Five pairs', created: '2026-11-18T20:00:00Z', expires: '2026-12-18T20:00:00Z', kept: false, keepDays: 30, bytes: 184000 })
    // A kept report never carries an end date.
    expect(parsed?.reports[1].expires).toBeNull()
    expect(parsed?.reports[1].keepDays).toBeNull()
    // A report's own keep time wins over the usual one.
    const own = parseReports({ reports: [{ id: 'ab12', title: 'S', created: '2026-11-18T20:00:00Z', keep_days: 90 }, { id: 'cd34', title: 'T', created: '2026-11-18T20:00:00Z' }] })
    expect(own?.keepDays).toBe(14)
    expect(own?.reports.map((r: JarvisReport) => r.keepDays)).toEqual([90, 14])
    expect(parsed).toMatchObject({ totalBytes: 184001, keepDays: 30, maxBytes: 200000000 })
  })

  it('is null when the answer isn’t a list of reports, and assumes 2 weeks when Jarvis doesn’t say', () => {
    expect(parseReports({ error: 'nope' })).toBeNull()
    expect(parseReports({ reports: [] })).toEqual({ reports: [], totalBytes: 0, keepDays: 14, maxBytes: 0 })
  })

  it('only lets plain ids through to Jarvis', () => {
    expect(isReportId('a1b2c3d4e5f60718')).toBe(true)
    expect(isReportId('rep-week_2')).toBe(true)
    expect(isReportId('../secrets')).toBe(false)
    expect(isReportId('')).toBe(false)
    expect(isReportId(7)).toBe(false)
  })
})

describe('GET /reports/:id', () => {
  it('serves the report as a page that can’t run scripts or load anything from outside', async () => {
    const res = await callApi(createApi(createMockSource()), 'GET', '/reports/rep-week')
    expect(res.statusCode).toBe(200)
    expect(res.headers['content-type']).toBe('text/html; charset=utf-8')
    expect(res.headers['content-security-policy']).toBe(REPORT_CSP)
    expect(REPORT_CSP).toContain("default-src 'none'")
    expect(REPORT_CSP).toContain('sandbox')
    expect(REPORT_CSP).not.toContain('allow-scripts')
    expect(REPORT_CSP).not.toContain('allow-same-origin')
    expect(res.headers['x-content-type-options']).toBe('nosniff')
    expect(res.headers['cache-control']).toBe('private, no-store')
    expect(res.body).toContain('<h1>Week in review</h1>')
  })

  it('says so plainly when the report is gone, with the same locked-down headers', async () => {
    const res = await callApi(createApi(createMockSource()), 'GET', '/reports/not-there')
    expect(res.statusCode).toBe(404)
    expect(res.headers['content-security-policy']).toBe(REPORT_CSP)
    expect(res.body).toContain('This report was deleted or has expired.')
  })

  it('never asks Jarvis for an id that isn’t one', async () => {
    const source = createMockSource()
    const asked = vi.spyOn(source, 'reportHtml')
    const res = await callApi(createApi(source), 'GET', '/reports/..%2Fmemory.md')
    expect(res.statusCode).toBe(404)
    expect(asked).not.toHaveBeenCalled()
  })
})

describe('POST /api/jarvis/reports', () => {
  it('keeps a report, which clears its end date, and lets it go again', async () => {
    const api = createApi(createMockSource())
    const keep = await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-speakers', keep: true }))
    expect(keep.json()).toEqual({ ok: true, message: 'Keeping it until you change that' })
    let snap = (await callApi(api, 'GET', '/api/snapshot')).json()
    let row = snap.reports.reports.find((r: JarvisReport) => r.id === 'rep-speakers')
    expect(row).toMatchObject({ kept: true, expires: null })
    await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-speakers', keep: false }))
    snap = (await callApi(api, 'GET', '/api/snapshot')).json()
    row = snap.reports.reports.find((r: JarvisReport) => r.id === 'rep-speakers')
    expect(row.kept).toBe(false)
    expect(row.keepDays).toBe(14)
    expect(typeof row.expires).toBe('string')
  })

  it('keeps a report for 1 or 3 months, and refuses other lengths', async () => {
    const api = createApi(createMockSource())
    const month = await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-speakers', days: 30 }))
    expect(month.json()).toEqual({ ok: true, message: 'Keeping it 1 month' })
    const row = (await callApi(api, 'GET', '/api/snapshot')).json().reports.reports.find((r: JarvisReport) => r.id === 'rep-speakers')
    expect(row).toMatchObject({ kept: false, keepDays: 30 })
    expect(Date.parse(row.expires) - Date.parse(row.created)).toBe(30 * 86_400_000)
    expect((await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-speakers', days: 7 }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-speakers' }))).statusCode).toBe(400)
  })

  it('deletes a report, so its page is gone and the room is given back', async () => {
    const api = createApi(createMockSource())
    const before = (await callApi(api, 'GET', '/api/snapshot')).json().reports
    const res = await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'delete', id: 'rep-trip' }))
    expect(res.json()).toEqual({ ok: true, message: 'Deleted' })
    const after = (await callApi(api, 'GET', '/api/snapshot')).json().reports
    expect(after.reports.map((r: JarvisReport) => r.id)).toEqual(['rep-speakers', 'rep-week'])
    expect(after.totalBytes).toBe(before.totalBytes - 412_000)
    expect((await callApi(api, 'GET', '/reports/rep-trip')).statusCode).toBe(404)
  })

  it('needs the page’s header and a well-formed change', async () => {
    const api = createApi(createMockSource())
    const body = JSON.stringify({ op: 'delete', id: 'rep-trip' })
    expect((await callApi(api, 'POST', '/api/jarvis/reports', {}, body)).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'keep', id: 'rep-trip' }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/reports', ACTION_HEADER, JSON.stringify({ op: 'delete', id: '../x' }))).statusCode).toBe(400)
  })
})

describe('live reports', () => {
  /** A live source whose Jarvis answers with what `answer` returns. */
  function liveWith(answer: (url: string, init?: RequestInit) => Response) {
    const fetch = vi.fn(async (url: string, init?: RequestInit) => answer(String(url), init))
    return { source: createLiveSource(config, { fetch }), fetch }
  }

  it('fetches a report’s HTML from Jarvis with the caller’s login', async () => {
    const { source, fetch } = liveWith(() => new Response('<h1>Hi</h1>'))
    expect(await source.reportHtml('ab12', { login: 'me@example.com' })).toEqual({ html: '<h1>Hi</h1>', gone: false })
    const [url, init] = fetch.mock.calls[0]
    expect(url).toBe(`${config.jarvisApiUrl}/reports/ab12`)
    expect((init?.headers as Record<string, string>)['tailscale-user-login']).toBe('me@example.com')
  })

  it('tells a deleted report from Jarvis not answering', async () => {
    const gone = liveWith(() => new Response('{"error":"gone"}', { status: 404 }))
    expect(await gone.source.reportHtml('ab12', { login: 'me@example.com' })).toEqual({ html: null, gone: true })
    const down = liveWith(() => { throw new Error('connect ECONNREFUSED') })
    expect(await down.source.reportHtml('ab12', { login: 'me@example.com' })).toEqual({ html: null, gone: false })
    expect(await down.source.reportHtml('ab12', {})).toEqual({ html: null, gone: false })
  })

  it('sends Keep and Delete to Jarvis’s own paths', async () => {
    const { source, fetch } = liveWith((url) => {
      if (url.endsWith('/keep')) return new Response(JSON.stringify({ report: { id: 'ab12', title: 'Speakers', created: '2026-11-18T20:00:00Z', kept: true, bytes: 5 } }))
      return new Response(JSON.stringify({ ok: true }))
    })
    const kept = await source.changeReport({ op: 'keep', id: 'ab12', keep: true }, { login: 'me@example.com' })
    expect(kept).toMatchObject({ ok: true, message: 'Keeping it until you change that', report: { id: 'ab12', kept: true, expires: null } })
    expect(fetch.mock.calls[0][0]).toBe(`${config.jarvisApiUrl}/reports/ab12/keep`)
    expect(fetch.mock.calls[0][1]?.body).toBe(JSON.stringify({ keep: true }))
    const deleted = await source.changeReport({ op: 'delete', id: 'ab12' }, { login: 'me@example.com' })
    expect(deleted).toEqual({ ok: true, message: 'Deleted' })
    expect(fetch.mock.calls[1][0]).toBe(`${config.jarvisApiUrl}/reports/ab12/delete`)
    const quarter = await source.changeReport({ op: 'keep', id: 'ab12', days: 90 }, { login: 'me@example.com' })
    expect(quarter.message).toBe('Keeping it 3 months')
    expect(fetch.mock.calls[2][1]?.body).toBe(JSON.stringify({ days: 90 }))
  })

  it('refuses a change without a Tailscale login', async () => {
    const { source, fetch } = liveWith(() => new Response('{}'))
    expect((await source.changeReport({ op: 'delete', id: 'ab12' }, {})).ok).toBe(false)
    expect(fetch).not.toHaveBeenCalled()
  })
})
