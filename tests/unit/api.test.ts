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

describe('Jarvis memory', () => {
  it('lists facts, searches, remembers and forgets (sample data)', async () => {
    const api = createApi(createMockSource())
    const memory = (await callApi(api, 'GET', '/api/jarvis/memory')).json().memory
    expect(memory.facts.length).toBeGreaterThan(2)
    expect(memory.turns).toBeGreaterThan(0)
    const hits = (await callApi(api, 'GET', '/api/jarvis/memory/search?q=big%20light')).json().hits
    expect(hits.length).toBeGreaterThan(0)
    expect(hits.every((h: { text: string }) => /big|light/i.test(h.text))).toBe(true)

    expect((await callApi(api, 'POST', '/api/jarvis/memory', {}, '{"op":"remember","text":"x"}')).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/memory', ACTION_HEADER, '{"op":"remember","text":"  "}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/memory', ACTION_HEADER, '{"op":"remember","text":"Likes oat milk"}')).json().ok).toBe(true)
    const after = (await callApi(api, 'GET', '/api/jarvis/memory')).json().memory.facts
    const added = after.find((f: { text: string }) => f.text === 'Likes oat milk')
    expect(added.from).toBe('you')
    expect((await callApi(api, 'POST', '/api/jarvis/memory', ACTION_HEADER, JSON.stringify({ op: 'forget', id: added.id }))).json().ok).toBe(true)
    const gone = (await callApi(api, 'GET', '/api/jarvis/memory')).json().memory.facts
    expect(gone.some((f: { id: string }) => f.id === added.id)).toBe(false)
  })

  it("passes the caller's login on to every memory call", async () => {
    const seen: unknown[] = []
    const source = {
      ...createMockSource(),
      memory: async (caller: unknown) => { seen.push(caller); return null },
      searchMemory: async (_q: string, caller: unknown) => { seen.push(caller); return [] },
      changeMemory: async (_c: unknown, caller: unknown) => { seen.push(caller); return { ok: true, message: 'ok' } },
    }
    const api = createApi(source)
    const login = { 'tailscale-user-login': 'dylan@example.com' }
    await callApi(api, 'GET', '/api/jarvis/memory', login)
    await callApi(api, 'GET', '/api/jarvis/memory/search?q=a', login)
    await callApi(api, 'POST', '/api/jarvis/memory', { ...ACTION_HEADER, ...login }, '{"op":"forget","id":"f1"}')
    expect(seen).toEqual([{ login: 'dylan@example.com' }, { login: 'dylan@example.com' }, { login: 'dylan@example.com' }])
  })
})

describe('Jarvis voice', () => {
  it('reads the voice, plays a sample, and saves a new one (sample data)', async () => {
    const api = createApi(createMockSource())
    const voice = (await callApi(api, 'GET', '/api/jarvis/voice')).json().voice
    expect(voice.voice).toBe('bm_george')
    expect(voice.voices.some((v: { id: string; accent: string }) => v.id === 'af_heart' && v.accent === 'us')).toBe(true)

    const sample = await callApi(api, 'GET', '/api/jarvis/voice/sample?voice=bm_lewis&speed=1.1&voice2=bm_george&mix=0.3')
    expect(sample.statusCode).toBe(200)
    expect(sample.headers['content-type']).toBe('audio/wav')
    expect(sample.body.startsWith('RIFF')).toBe(true)
    expect((await callApi(api, 'GET', '/api/jarvis/voice/sample?voice=bm_lewis&speed=3')).statusCode).toBe(400)

    const choice = JSON.stringify({ voice: 'bm_lewis', speed: 1.1, blend: { voice2: 'bm_george', mix: 0.3 } })
    expect((await callApi(api, 'POST', '/api/jarvis/voice', {}, choice)).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/voice', ACTION_HEADER, '{"voice":"bm_lewis","speed":2}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/voice', ACTION_HEADER, '{"voice":"bm_lewis","blend":{"voice2":"bm_george","mix":1}}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/voice', ACTION_HEADER, '{"voice":"zz_nobody"}')).statusCode).toBe(502)
    expect((await callApi(api, 'POST', '/api/jarvis/voice', ACTION_HEADER, choice)).json().ok).toBe(true)
    const after = (await callApi(api, 'GET', '/api/jarvis/voice')).json().voice
    expect(after).toMatchObject({ voice: 'bm_lewis', speed: 1.1, blend: { voice2: 'bm_george', mix: 0.3 } })
  })

  it("passes the caller's login on to every voice call", async () => {
    const seen: unknown[] = []
    const source = {
      ...createMockSource(),
      voice: async (caller: unknown) => { seen.push(caller); return null },
      setVoice: async (_c: unknown, caller: unknown) => { seen.push(caller); return { ok: true, message: 'ok' } },
      voiceSample: async (_c: unknown, caller: unknown) => { seen.push(caller); return { ok: false as const, message: 'no' } },
    }
    const api = createApi(source)
    const login = { 'tailscale-user-login': 'dylan@example.com' }
    expect((await callApi(api, 'GET', '/api/jarvis/voice', login)).json()).toEqual({ voice: null })
    await callApi(api, 'POST', '/api/jarvis/voice', { ...ACTION_HEADER, ...login }, '{"voice":"bm_george","speed":1}')
    expect((await callApi(api, 'GET', '/api/jarvis/voice/sample?voice=bm_george', login)).statusCode).toBe(502)
    expect(seen).toEqual([{ login: 'dylan@example.com' }, { login: 'dylan@example.com' }, { login: 'dylan@example.com' }])
  })
})

describe('Jarvis approvals', () => {
  it('a reply waits on an approval, which the page answers, then carries on (sample data)', async () => {
    const source = createMockSource()
    const api = createApi(source)
    const events: { type: string; approval?: { id: string }; ok?: boolean; by?: string }[] = []
    let asked: (id: string) => void = () => {}
    const approvalId = new Promise<string>((resolve) => { asked = resolve })
    const chatting = source.chat('please restart jarvis', {}, (event: { type: string; approval?: { id: string } }) => {
      events.push(event)
      if (event.type === 'approval') asked(event.approval!.id)
    })
    const id = await approvalId
    // A reload would see it waiting.
    expect((await callApi(api, 'GET', '/api/jarvis/approvals')).json().pending).toMatchObject([{ id, tool: 'run_command' }])
    // Needs the page header and a proper body.
    expect((await callApi(api, 'POST', '/api/jarvis/approve', {}, JSON.stringify({ id, ok: true }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/approve', ACTION_HEADER, JSON.stringify({ id, ok: 'yes' }))).statusCode).toBe(400)
    const res = await callApi(api, 'POST', '/api/jarvis/approve', ACTION_HEADER, JSON.stringify({ id, ok: true }))
    expect(res.json()).toEqual({ ok: true, message: 'Approved' })
    await chatting
    expect(events).toContainEqual({ type: 'approval_done', id, ok: true, by: 'page' })
    expect(events.at(-1)).toEqual({ type: 'done', ok: true })
    // Answered once; a second answer is refused.
    expect((await callApi(api, 'POST', '/api/jarvis/approve', ACTION_HEADER, JSON.stringify({ id, ok: false }))).statusCode).toBe(409)
    expect((await callApi(api, 'GET', '/api/jarvis/approvals')).json().pending).toEqual([])
  })
})

describe('POST /api/jarvis/warm', () => {
  it('needs the page header, and passes the login on', async () => {
    let seen: unknown = null
    const source = { ...createMockSource(), warm: async (caller: unknown) => { seen = caller; return true } }
    const api = createApi(source)
    expect((await callApi(api, 'POST', '/api/jarvis/warm', {})).statusCode).toBe(403)
    const res = await callApi(api, 'POST', '/api/jarvis/warm', { ...ACTION_HEADER, 'tailscale-user-login': 'dylan@example.com' })
    expect(res.json()).toEqual({ ok: true })
    expect(seen).toEqual({ login: 'dylan@example.com' })
  })
})

describe('POST /api/jarvis/chat and GET /api/jarvis/history', () => {
  it('refuses requests without the page header, and empty text', async () => {
    const api = createApi(createMockSource())
    expect((await callApi(api, 'POST', '/api/jarvis/chat', {}, '{"text":"hi"}')).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, '{"text":" "}')).statusCode).toBe(400)
  })

  it('streams the reply as one JSON event per line, ending with done, and keeps it in history', async () => {
    const api = createApi(createMockSource())
    const res = await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, '{"text":"weather?"}')
    expect(res.headers['content-type']).toContain('application/x-ndjson')
    const events = res.body.trim().split('\n').map((line) => JSON.parse(line))
    expect(events.length).toBeGreaterThan(3)
    expect(events.at(-1)).toEqual({ type: 'done', ok: true })
    const reply = events.filter((e) => e.type === 'delta').map((e) => e.text).join('')
    expect(reply).toContain('68 and clear')
    const history = (await callApi(api, 'GET', '/api/jarvis/history')).json().turns
    expect(history.map((t: { role: string }) => t.role)).toEqual(['user', 'jarvis'])
    expect(history[1].text).toBe(reply)
  })

  it("passes the caller's Tailscale login to the source", async () => {
    let seen: unknown = null
    const source = {
      ...createMockSource(),
      chat: async (text: string, caller: unknown, onEvent: (e: unknown) => void) => { seen = { text, caller }; onEvent({ type: 'done', ok: true }) },
    }
    await callApi(createApi(source), 'POST', '/api/jarvis/chat', { ...ACTION_HEADER, 'tailscale-user-login': 'dylan@example.com' }, '{"text":"hi"}')
    expect(seen).toEqual({ text: 'hi', caller: { login: 'dylan@example.com' } })
  })
}, 15_000)

describe('POST /api/home/control', () => {
  it('refuses requests without the page header, and bodies without entity and command', async () => {
    const api = createApi(createMockSource())
    expect((await callApi(api, 'POST', '/api/home/control', {}, '{"entity":"light.x","command":"toggle"}')).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/home/control', ACTION_HEADER, '{"entity":"light.x"}')).statusCode).toBe(400)
  })

  it("passes the command and the caller's Tailscale login to the source", async () => {
    let seen: unknown = null
    const source = { ...createMockSource(), control: async (...args: unknown[]) => { seen = args; return { ok: true, message: 'Done' } } }
    const res = await callApi(createApi(source), 'POST', '/api/home/control', { ...ACTION_HEADER, 'tailscale-user-login': 'd@example.com' }, '{"entity":"light.lamp","command":"brightness","value":0.5}')
    expect(res.statusCode).toBe(200)
    expect(seen).toEqual(['light.lamp', 'brightness', 0.5, { login: 'd@example.com' }])
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

describe('POST /api/digest/refresh', () => {
  it('needs the page header, and asks Jarvis as the caller', async () => {
    let seen: unknown = null
    const source = { ...createMockSource(), refreshDigest: async (caller: unknown) => { seen = caller; return { running: true, lastWrite: null } } }
    const api = createApi(source)
    expect((await callApi(api, 'POST', '/api/digest/refresh')).statusCode).toBe(403)
    const res = await callApi(api, 'POST', '/api/digest/refresh', { ...ACTION_HEADER, 'tailscale-user-login': 'dylan@example.com' })
    expect(res.json()).toEqual({ running: true, lastWrite: null })
    expect(seen).toEqual({ login: 'dylan@example.com' })
  })
})

describe('POST /api/money/picks', () => {
  it('needs the page header, saves a pick, and shows it in the snapshot', async () => {
    const api = createApi(createMockSource())
    const body = JSON.stringify({ op: 'pick', id: 'x5', category: 'Lessons', merchant: 'Venmo Alex', date: '2026-11-10T10:00:00Z', amount: 120 })
    expect((await callApi(api, 'POST', '/api/money/picks', {}, body)).statusCode).toBe(403)
    const res = await callApi(api, 'POST', '/api/money/picks', ACTION_HEADER, body)
    expect(res.statusCode).toBe(200)
    const snap = (await callApi(api, 'GET', '/api/snapshot')).json()
    expect(snap.moneyPicks.picks.map((p: { category: string }) => p.category)).toEqual(['Lessons'])
  })

  it('answers 400 to a bad change', async () => {
    const api = createApi(createMockSource())
    expect((await callApi(api, 'POST', '/api/money/picks', ACTION_HEADER, 'nope')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/money/picks', ACTION_HEADER, '{"op":"pick"}')).statusCode).toBe(400)
  })
})
