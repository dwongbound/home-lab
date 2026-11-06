// The API handler: routes, the action guard, one action at a time, and
// that the Home Assistant token never appears in a response.
import { describe, expect, it } from 'vitest'
import { createApi } from '../../server/app.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { loadConfig } from '../../server/config.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }

describe('GET /api/snapshot', () => {
  it('returns the snapshot, uncached', async () => {
    const res = await callApi(createApi(createMockSource()), 'GET', '/api/snapshot')
    expect(res.statusCode).toBe(200)
    expect(res.headers['cache-control']).toBe('no-store')
    expect(res.json().host.name).toBe('jarvis')
  })

  it('passes non-API paths to the next handler', async () => {
    const api = createApi(createMockSource())
    let passed = false
    await api({ method: 'GET', url: '/assets/app.js', headers: {} }, {}, () => { passed = true })
    expect(passed).toBe(true)
  })
})

describe('POST /api/actions/:name', () => {
  it('refuses requests without the page header', async () => {
    const res = await callApi(createApi(createMockSource()), 'POST', '/api/actions/ollama-unload')
    expect(res.statusCode).toBe(403)
  })

  it('404s unknown actions', async () => {
    const res = await callApi(createApi(createMockSource()), 'POST', '/api/actions/reboot', ACTION_HEADER)
    expect(res.statusCode).toBe(404)
  })

  it('runs one action at a time', async () => {
    const api = createApi(createMockSource())
    const first = callApi(api, 'POST', '/api/actions/ollama-unload', ACTION_HEADER)
    const second = await callApi(api, 'POST', '/api/actions/ollama-load', ACTION_HEADER)
    expect(second.statusCode).toBe(409)
    expect((await first).statusCode).toBe(200)
  })
})

describe('secrets', () => {
  it('never puts the Home Assistant token in a snapshot', async () => {
    const token = 'super-secret-long-lived-token'
    const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: token })
    const fakeFetch = async () => new Response('{}', { status: 200 })
    const fakeExec = async () => ({ stdout: 'active\n' })
    const fakeStatfs = async () => ({ bavail: 1, bsize: 1, blocks: 2 })
    const source = createLiveSource(config, { fetch: fakeFetch, execFile: fakeExec, statfs: fakeStatfs })
    const res = await callApi(createApi(source), 'GET', '/api/snapshot')
    expect(res.statusCode).toBe(200)
    expect(res.body).not.toContain(token)
  })
})
