// The API handler: routes, the action guard, one action at a time, and
// that the Home Assistant token never appears in a response.
import { describe, expect, it, vi } from 'vitest'
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

  it('shares one build between callers until something changes', async () => {
    const source = createMockSource()
    const build = vi.spyOn(source, 'snapshot')
    const api = createApi(source)
    await Promise.all([callApi(api, 'GET', '/api/snapshot'), callApi(api, 'GET', '/api/snapshot')])
    await callApi(api, 'GET', '/api/snapshot')
    expect(build).toHaveBeenCalledTimes(1)
    await callApi(api, 'POST', '/api/actions/ollama-unload', ACTION_HEADER)
    await callApi(api, 'GET', '/api/snapshot')
    expect(build).toHaveBeenCalledTimes(2)
  })
})

describe('GET / (the metrics page)', () => {
  it('shows services, the machine and running jobs, with names escaped', async () => {
    const source = createMockSource()
    const snap = await source.snapshot()
    snap.services[0].name = '<b>HA</b>'
    vi.spyOn(source, 'snapshot').mockResolvedValue(snap)
    const res = await callApi(createApi(source), 'GET', '/')
    expect(res.statusCode).toBe(200)
    expect(res.headers['content-type']).toContain('text/html')
    expect(res.body).toContain('&#60;b&#62;HA&#60;/b&#62;')
    expect(res.body).not.toContain('<b>HA')
    expect(res.body).toContain('Graphics card')
    expect(res.body).toContain('C: drive')
    expect(res.body).toContain(snap.jobs.running[0].label)
    expect(res.body).not.toContain('<script')
  })

  it('answers 404 for any other page path', async () => {
    expect((await callApi(createApi(createMockSource()), 'GET', '/talk')).statusCode).toBe(404)
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

  it('tells Jarvis when the asker closes the app before the reply is done, and not when the reply finished first', async () => {
    const left: unknown[] = []
    let finish = () => {}
    const source = {
      ...createMockSource(),
      chat: async (_text: string, _caller: unknown, onEvent: (e: unknown) => void) => {
        onEvent({ type: 'turn', id: 41 })
        await new Promise<void>((resolve) => { finish = resolve })
        onEvent({ type: 'done', ok: true })
      },
      chatLeft: async (...args: unknown[]) => { left.push(args) },
    }
    // A response that can be closed from the client's side, like a phone going away.
    const listeners: Record<string, () => void> = {}
    const res = { destroyed: false, writableEnded: false, writeHead() {}, write() {}, end() { this.writableEnded = true }, on(event: string, fn: () => void) { listeners[event] = fn } }
    const req = { method: 'POST', url: '/api/jarvis/chat', headers: { ...ACTION_HEADER, 'tailscale-user-login': 'd@example.com' }, async *[Symbol.asyncIterator]() { yield '{"text":"hi"}' } }
    const handled = createApi(source)(req as never, res as never)
    await vi.waitFor(() => expect(listeners.close).toBeTypeOf('function'))
    await new Promise((resolve) => setTimeout(resolve, 0))
    res.destroyed = true
    listeners.close()
    expect(left).toEqual([[41, { login: 'd@example.com' }]])
    finish()
    await handled
    // The socket closing after a finished reply is the normal end, not someone leaving.
    listeners.close()
    expect(left).toHaveLength(1)
  })

  it('pages the history: the newest turns, the ones before a turn, a window around one, and 400 on a bad ask', async () => {
    const api = createApi(createMockSource())
    for (const text of ['one', 'two', 'three']) await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text }))
    const ids = (path: string) => {
      const body = callApi(api, 'GET', path).then((res) => res.json())
      return body.then((page: { turns: { id: number }[]; hasMore: boolean; hasNewer: boolean }) => ({ ids: page.turns.map((t) => t.id), hasMore: page.hasMore, hasNewer: page.hasNewer }))
    }
    expect(await ids('/api/jarvis/history')).toEqual({ ids: [1, 2, 3, 4, 5, 6], hasMore: false, hasNewer: false })
    expect(await ids('/api/jarvis/history?limit=2')).toEqual({ ids: [5, 6], hasMore: true, hasNewer: false })
    expect(await ids('/api/jarvis/history?limit=2&before=5')).toEqual({ ids: [3, 4], hasMore: true, hasNewer: false })
    expect(await ids('/api/jarvis/history?limit=2&before=3')).toEqual({ ids: [1, 2], hasMore: false, hasNewer: false })
    expect(await ids('/api/jarvis/history?limit=2&around=3')).toEqual({ ids: [2, 3], hasMore: true, hasNewer: true })
    expect(await ids('/api/jarvis/history?limit=2&around=99')).toEqual({ ids: [5, 6], hasMore: true, hasNewer: false })
    for (const bad of ['limit=0', 'limit=101', 'before=abc', 'around=-1', 'before=2&around=3']) {
      expect((await callApi(api, 'GET', `/api/jarvis/history?${bad}`)).statusCode).toBe(400)
    }
  }, 20_000)

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

describe('Sleep from the Watch', () => {
  it('gives the last nights or one night, and refuses a bad ask', async () => {
    const api = createApi(createMockSource())
    const week = (await callApi(api, 'GET', '/api/jarvis/health/sleep')).json().nights
    expect(week).toHaveLength(7)
    expect(week[0]).toMatchObject({ score: 78, scoreBand: 'good', scoreSource: 'jarvis' })
    expect(week[0].stages.length).toBeGreaterThan(0)
    expect((await callApi(api, 'GET', '/api/jarvis/health/sleep?days=99')).json().nights).toHaveLength(30)
    const one = (await callApi(api, 'GET', '/api/jarvis/health/sleep?night=2026-11-17')).json().nights
    expect(one.map((night: { night: string }) => night.night)).toEqual(['2026-11-17'])
    expect((await callApi(api, 'GET', '/api/jarvis/health/sleep?night=monday')).statusCode).toBe(400)
    expect((await callApi(api, 'GET', '/api/jarvis/health/sleep?days=some')).statusCode).toBe(400)
  })

  it('stores a night from the app, needs the header, and says what is wrong with a bad one', async () => {
    const api = createApi(createMockSource())
    const night = { night: '2026-11-17', stages: [{ stage: 'deep', start: '2026-11-17T01:00:00-08:00', end: '2026-11-17T02:00:00-08:00' }], hrvMs: 61 }
    expect((await callApi(api, 'POST', '/api/jarvis/health/sleep', {}, JSON.stringify(night))).statusCode).toBe(403)
    const saved = await callApi(api, 'POST', '/api/jarvis/health/sleep', { 'x-home-lab': '1' }, JSON.stringify(night))
    expect(saved.statusCode).toBe(200)
    expect(saved.json()).toMatchObject({ ok: true, message: 'Saved', night: { night: '2026-11-17', vitals: { hrvMs: 61 } } })
    const back = (await callApi(api, 'GET', '/api/jarvis/health/sleep?night=2026-11-17')).json().nights
    expect(back[0].vitals.hrvMs).toBe(61)
    const bad = await callApi(api, 'POST', '/api/jarvis/health/sleep', { 'x-home-lab': '1' }, JSON.stringify({ ...night, hrvMs: 900 }))
    expect(bad.statusCode).toBe(400)
    expect(bad.json()).toEqual({ ok: false, message: 'hrvMs must be between 1 and 300' })
    expect((await callApi(api, 'POST', '/api/jarvis/health/sleep', { 'x-home-lab': '1' }, 'not json')).statusCode).toBe(400)
  })

  it('passes on Jarvis refusing a night as a 400, and his being away as a 502', async () => {
    const night = { night: '2026-11-17', stages: [{ stage: 'deep', start: '2026-11-17T01:00:00-08:00', end: '2026-11-17T02:00:00-08:00' }] }
    const refusing = { ...createMockSource(), saveSleepNight: async () => ({ ok: false, refused: true, message: 'stages overlap' }) }
    const refused = await callApi(createApi(refusing), 'POST', '/api/jarvis/health/sleep', { 'x-home-lab': '1' }, JSON.stringify(night))
    expect(refused.statusCode).toBe(400)
    expect(refused.json()).toEqual({ ok: false, message: 'stages overlap', night: null })
    const away = { ...createMockSource(), saveSleepNight: async () => ({ ok: false, message: 'Jarvis is not answering' }) }
    expect((await callApi(createApi(away), 'POST', '/api/jarvis/health/sleep', { 'x-home-lab': '1' }, JSON.stringify(night))).statusCode).toBe(502)
  })
})

describe('Diet screen (meal log)', () => {
  it('gives a day and a week (sample data), and refuses a date that isn\'t one', async () => {
    const api = createApi(createMockSource())
    const day = (await callApi(api, 'GET', '/api/jarvis/nutrition/day?date=2026-11-17')).json().day
    expect(day.date).toBe('2026-11-17')
    expect(day.items.length).toBeGreaterThan(0)
    expect(day.items[0]).toHaveProperty('hasPhoto')
    const today = (await callApi(api, 'GET', '/api/jarvis/nutrition/day')).json().day
    expect(today.date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    const week = (await callApi(api, 'GET', '/api/jarvis/nutrition/week?start=2026-11-15')).json().week
    expect(week.start).toBe('2026-11-15')
    expect(week.days).toHaveLength(7)
    expect(week.days[0]).toMatchObject({ protein: expect.any(Number), proteinGoal: 140 })
    const run = (await callApi(api, 'GET', '/api/jarvis/nutrition/days?end=2026-11-17&count=3')).json()
    expect(run.days.map((d: { date: string }) => d.date)).toEqual(['2026-11-17', '2026-11-16', '2026-11-15'])
    expect(run.earliest).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/days')).json().days).toHaveLength(7)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/days?count=99')).json().days).toHaveLength(14)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/days?count=lots')).statusCode).toBe(400)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/days?end=tuesday')).statusCode).toBe(400)

    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/day?date=yesterday')).statusCode).toBe(400)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/week?start=11/15')).statusCode).toBe(400)
  })

  it('serves a meal photo or its thumbnail, 404 when the meal has none', async () => {
    const api = createApi(createMockSource())
    const photo = await callApi(api, 'GET', '/api/jarvis/nutrition/photo/m1?size=thumb')
    expect(photo.statusCode).toBe(200)
    expect(photo.headers['content-type']).toBe('image/png')
    expect(photo.headers['cache-control']).toBe('private, max-age=86400')
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/photo/m2')).statusCode).toBe(200)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/photo/m3')).statusCode).toBe(404)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/photo/m1?size=huge')).statusCode).toBe(400)
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/photo/..%2Fsecret')).statusCode).toBe(400)
  })

  it("passes the date and the caller's login on to the source", async () => {
    const seen: unknown[] = []
    const source = {
      ...createMockSource(),
      nutritionDay: async (date: string, caller: unknown) => { seen.push([date, caller]); return null },
      nutritionWeek: async (start: string, caller: unknown) => { seen.push([start, caller]); return null },
      nutritionDays: async () => null,
    }
    const api = createApi(source)
    const login = { 'tailscale-user-login': 'dylan@example.com' }
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/day?date=2026-11-17', login)).json()).toEqual({ day: null })
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/week', login)).json()).toEqual({ week: null })
    expect((await callApi(api, 'GET', '/api/jarvis/nutrition/days', login)).json()).toEqual({ days: null, earliest: null })
    expect(seen).toEqual([['2026-11-17', { login: 'dylan@example.com' }], ['', { login: 'dylan@example.com' }]])
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
    // Answered once; a second answer says it's gone, so every screen drops the card.
    const late = await callApi(api, 'POST', '/api/jarvis/approve', ACTION_HEADER, JSON.stringify({ id, ok: false }))
    expect(late.statusCode).toBe(410)
    expect(late.json()).toMatchObject({ ok: false, gone: true })
    expect((await callApi(api, 'GET', '/api/jarvis/approvals')).json().pending).toEqual([])
  })
})

describe('POST /api/jarvis/sleep', () => {
  it('needs the page header and a yes or no, and passes the screen and login on', async () => {
    let seen: unknown[] = []
    const source = { ...createMockSource(), setSleep: async (...args: unknown[]) => { seen = args; return { ok: true, message: 'Good night' } } }
    const api = createApi(source)
    const headers = { ...ACTION_HEADER, 'tailscale-user-login': 'dylan@example.com' }
    expect((await callApi(api, 'POST', '/api/jarvis/sleep', {}, JSON.stringify({ asleep: true }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/sleep', headers, JSON.stringify({ asleep: 'yes' }))).statusCode).toBe(400)
    const res = await callApi(api, 'POST', '/api/jarvis/sleep', headers, JSON.stringify({ asleep: true, source: 'tv' }))
    expect(res.json()).toEqual({ ok: true, message: 'Good night' })
    expect(seen).toEqual([true, 'tv', { login: 'dylan@example.com' }])
    await callApi(api, 'POST', '/api/jarvis/sleep', headers, JSON.stringify({ asleep: false, source: 'Not A Screen!' }))
    expect(seen).toEqual([false, 'page', { login: 'dylan@example.com' }])
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

describe('POST /api/jarvis/jobs/stop', () => {
  it('stops a running job once, and says gone the second time', async () => {
    const api = createApi(createMockSource())
    const stop = (headers: Record<string, string>, body: unknown) => callApi(api, 'POST', '/api/jarvis/jobs/stop', headers, JSON.stringify(body))
    expect((await stop({}, { id: 'r1' })).statusCode).toBe(403)
    expect((await stop(ACTION_HEADER, { id: '../approve' })).statusCode).toBe(400)
    expect((await stop(ACTION_HEADER, {})).statusCode).toBe(400)
    const done = await stop(ACTION_HEADER, { id: 'r1' })
    expect(done.statusCode).toBe(200)
    expect(done.json()).toEqual({ ok: true, message: 'Stopped' })
    // It leaves the running list and shows under what finished today.
    const jobs = (await callApi(api, 'GET', '/api/snapshot')).json().jobs
    expect(jobs.running.map((task: { id: string }) => task.id)).toEqual(['r2'])
    expect(jobs.finished[0]).toMatchObject({ id: 'r1', state: 'stopped' })
    const again = await stop(ACTION_HEADER, { id: 'r1' })
    expect(again.statusCode).toBe(410)
    expect(again.json()).toEqual({ ok: false, gone: true, message: 'That one already finished' })
    expect((await stop(ACTION_HEADER, { id: 'nope' })).statusCode).toBe(410)
  })
})
