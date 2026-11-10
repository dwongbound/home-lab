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

describe('POST /api/jarvis/ask', () => {
  it('refuses requests without the page header', async () => {
    const res = await callApi(createApi(createMockSource()), 'POST', '/api/jarvis/ask', {}, '{"text":"hi"}')
    expect(res.statusCode).toBe(403)
  })

  it('needs some text', async () => {
    const api = createApi(createMockSource())
    expect((await callApi(api, 'POST', '/api/jarvis/ask', ACTION_HEADER, '{"text":"  "}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/ask', ACTION_HEADER, 'not json')).statusCode).toBe(400)
  })

  it("passes the caller's Tailscale login to the source", async () => {
    let seen: unknown = null
    const source = { ...createMockSource(), ask: async (text: string, caller: unknown) => { seen = { text, caller }; return { ok: true, message: 'hello' } } }
    const res = await callApi(createApi(source), 'POST', '/api/jarvis/ask', { ...ACTION_HEADER, 'tailscale-user-login': 'dylan@example.com' }, '{"text":"hi"}')
    expect(res.json()).toEqual({ ok: true, message: 'hello' })
    expect(seen).toEqual({ text: 'hi', caller: { login: 'dylan@example.com' } })
  })
})

describe('POST /api/home', () => {
  it('refuses requests without the page header', async () => {
    const res = await callApi(createApi(createMockSource()), 'POST', '/api/home', {}, '{"id":"light.porch","command":"turn_on"}')
    expect(res.statusCode).toBe(403)
  })

  it('refuses anything outside the allow list before the source sees it', async () => {
    let called = false
    const source = { ...createMockSource(), home: async () => { called = true; return { ok: true, message: '' } } }
    const api = createApi(source)
    const bodies = [
      '{"id":"alarm_control_panel.house","command":"turn_off"}',
      '{"id":"light.porch","command":"unlock"}',
      '{"id":"light.porch; rm -rf","command":"turn_on"}',
      '{"id":"light.porch","command":"brightness","value":400}',
      'not json',
    ]
    for (const body of bodies) {
      expect((await callApi(api, 'POST', '/api/home', ACTION_HEADER, body)).statusCode).toBe(400)
    }
    expect(called).toBe(false)
  })

  it('changes a device and the next snapshot shows it', async () => {
    const api = createApi(createMockSource())
    const res = await callApi(api, 'POST', '/api/home', ACTION_HEADER, '{"id":"light.porch","command":"turn_on"}')
    expect(res.json()).toEqual({ ok: true, message: 'turned on' })
    const snap = (await callApi(api, 'GET', '/api/snapshot')).json()
    expect(snap.home.find((d: { id: string }) => d.id === 'light.porch').on).toBe(true)
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

  it('never puts the Home Assistant token in a Home answer', async () => {
    const token = 'super-secret-long-lived-token'
    const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: token })
    const fakeFetch = async () => new Response('nope', { status: 500 })
    const source = createLiveSource(config, { fetch: fakeFetch, execFile: async () => ({ stdout: '' }), statfs: async () => ({ bavail: 1, bsize: 1, blocks: 2 }) })
    const res = await callApi(createApi(source), 'POST', '/api/home', ACTION_HEADER, '{"id":"lock.front_door","command":"unlock"}')
    expect(res.statusCode).toBe(502)
    expect(res.body).not.toContain(token)
  })
})
