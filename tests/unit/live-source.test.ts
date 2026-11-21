// The live source with every probe faked: status rules, failures that
// shouldn't break the page, and the Ollama load/unload call.
import { describe, expect, it, vi } from 'vitest'
import { createLiveSource, jarvisSaid, parseKeepAlive } from '../../server/sources/live.mjs'
import { loadConfig } from '../../server/config.mjs'

const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })
const GB = 1024 ** 3

interface Fakes {
  ollamaModels?: unknown[]
  jarvisAnswers?: boolean
  jarvisStatusCode?: number
  haStatusCode?: number
  unitState?: string
  gpuFails?: boolean
  /** Jarvis's GET /schedule/today answer; undefined = an older Jarvis that 404s. */
  schedule?: unknown
  /** Jarvis's GET /jobs answer; undefined = an older Jarvis that 404s. */
  jobs?: unknown
  /** The version block in Jarvis's /health; undefined = an older Jarvis without one. */
  jarvisVersion?: unknown
}

/** A live source whose fetch/execFile/statfs answer as described. */
function liveWith({ ollamaModels = [], jarvisAnswers = true, jarvisStatusCode = 200, haStatusCode = 200, unitState = 'active', gpuFails = false, schedule, jobs, jarvisVersion }: Fakes) {
  const fetch = vi.fn(async (url: string, init?: RequestInit) => {
    if (url.endsWith('/api/ps')) return new Response(JSON.stringify({ models: ollamaModels }))
    if (url === `${config.jarvisApiUrl}/health`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return new Response(JSON.stringify({ ok: true, brain: 'claude', version: jarvisVersion }), { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/jobs`) {
      if (jobs === undefined) return new Response('not found', { status: 404 })
      return Response.json(jobs)
    }
    if (url.startsWith(`${config.jarvisApiUrl}/jobs/`)) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (url.endsWith('/jobs/done/stop')) return Response.json({ ok: false, gone: true, message: 'That job already finished.' }, { status: 410 })
      if (url.endsWith('/jobs/live/stop')) return Response.json({ ok: false, message: 'It\'s going live right now.' }, { status: 409 })
      return Response.json({ ok: true, detail: 'Stopped "Shorter greeting" and put things back as they were.' }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/schedule/today`) {
      if (schedule === undefined) return new Response('not found', { status: 404 })
      return Response.json(schedule)
    }
    if (url === `${config.jarvisApiUrl}/digest/refresh`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ running: true, lastWrite: '2026-11-10T09:16:11Z' }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/memory/facts`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (init?.method === 'POST') return Response.json({ ok: true, message: 'Forgotten' }, { status: jarvisStatusCode })
      return Response.json({ facts: [{ id: 'a', text: 'Likes knots', learned: '2026-11-10T11:30:00Z', from: 'nightly' }, { id: 'b' }], turns: 42, lastDistill: '2026-11-11T11:30:00Z' }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/memory/search?`)) {
      return Response.json({ hits: [{ chat: 'voice', role: 'assistant', text: 'Lamp is off.', at: 'b' }, { chat: 'x' }] })
    }
    if (url === `${config.jarvisApiUrl}/voice`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (init?.method === 'POST') return Response.json({ ok: true, message: 'Saved' }, { status: jarvisStatusCode })
      return Response.json({ voice: 'bm_george', speed: 1.1, blend: null, voices: [{ id: 'bm_george', name: 'George', accent: 'gb', gender: 'm' }, { id: 'af_heart' }, { name: 'broken' }] }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/voice/sample?`)) {
      return new Response(new Uint8Array([82, 73, 70, 70]), { headers: { 'content-type': 'audio/wav' } })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/nutrition/photo/`)) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (url.includes('/photo/9')) return Response.json({ error: 'no photo' }, { status: 404 })
      return new Response(new Uint8Array([1, 2, 3]), { headers: { 'content-type': 'image/jpeg; charset=binary' } })
    }
    if (url === `${config.jarvisApiUrl}/system`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ ram: { total_mb: 32000, used_mb: 9000, scope: 'pc', users: [{ name: 'Jarvis', role: 'The agent', mb: 2100 }] }, disks: [{ id: 'c', name: 'C: drive', used_gb: 200, total_gb: 238, users: [] }] }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/health/sleep`)) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      const night = { night: '2026-11-18', minutes: { asleep: 400 }, score: 72, score_source: 'jarvis', stages: [{ stage: 'rem', start: '2026-11-18T03:00:00-08:00', end: '2026-11-18T04:00:00-08:00' }] }
      if (init?.method === 'POST') {
        if (JSON.parse(String(init.body)).night === '2026-01-01') return Response.json({ error: 'night is too old' }, { status: 400 })
        return Response.json({ ok: true, night: '2026-11-18', summary: 'Sleep: 6 h 40 min', detail: night }, { status: jarvisStatusCode })
      }
      return Response.json({ nights: [{ night: '2026-11-17', minutes: { asleep: 380 }, score: 60 }, night] }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/nutrition/days`)) {
      const older = { date: '2026-11-16', goals: {}, totals: {}, items: [] }
      const newer = { date: '2026-11-17', goals: {}, totals: {}, items: [{ id: 4, at: '2026-11-17T08:00:00-08:00', name: 'Latte' }] }
      return Response.json({ days: [older, newer], earliest: '2026-10-02' }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/nutrition/day`)) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ date: '2026-11-17', goals: { calories: 1750 }, totals: { calories: 250, burned: 300 }, items: [{ id: 4, at: '2026-11-17T08:00:00-08:00', name: 'Latte', calories: 250, has_photo: true }] }, { status: jarvisStatusCode })
    }
    if (url.startsWith(`${config.jarvisApiUrl}/nutrition/week`)) {
      return Response.json({ start: '2026-11-15', days: [{ date: '2026-11-15', calories: 1600, goal: 1750, protein: 120.26, protein_goal: 140 }] })
    }
    if (url === `${config.jarvisApiUrl}/gpu`) {
      if (jarvisVersion === undefined) return new Response('not found', { status: 404 })
      return Response.json({ models: [{ name: 'Parakeet', role: 'Hears you', mb: 2430, loaded: true }, { name: 'Kokoro', role: 'His voice', mb: 900, loaded: true }, { name: 'Qwen3-ASR', role: 'Final transcript', mb: 4600, loaded: false }] })
    }
    if (url === `${config.jarvisApiUrl}/nutrition/today`) {
      return Response.json({ date: '2026-11-18', eaten: 1200, goal: 1750, left: 999, burned: null, protein: 90, protein_goal: 140, goal_source: 'config' })
    }
    if (url === `${config.jarvisApiUrl}/notices`) {
      return Response.json({ notices: [{ id: 'n1', kind: 'heads', title: 'Rain at 4', source: 'lookout' }, { id: 'n2', kind: 'nope', title: 'Dropped' }] }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/notices/keep`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (jarvisStatusCode === 404) return new Response('Not Found', { status: 404 })
      const asked = JSON.parse(String(init?.body ?? '{}'))
      if (asked.turn_id === 99) return Response.json({ ok: false, message: 'no such turn' }, { status: 404 })
      return Response.json({ ok: true, notice: { id: 'k7', kind: 'fyi', title: 'Call the shop', source: 'kept', turn_id: 7, kept: true } })
    }
    if (url === `${config.jarvisApiUrl}/notices/unkeep` || url === `${config.jarvisApiUrl}/notices/clear` || url === `${config.jarvisApiUrl}/push/register`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ ok: true }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/sleep`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ asleep: true }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/chat/warm`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ ok: true }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/chat/stream`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (jarvisStatusCode !== 200) return new Response('no', { status: jarvisStatusCode })
      // Split mid-line on purpose: the reader must join pieces before parsing.
      const pieces = [
        '{"type":"delta","text":"Lamp "}\n{"type":"del', 'ta","text":"is off."}\n',
        '{"type":"approval","id":"a1","tool":"run_command","summary":"ls","expires":"2026-11-11T12:20:00Z"}\n',
        '{"type":"approval","tool":"no id"}\n',
        '{"type":"approval_done","id":"a1","ok":true,"by":"voice"}\n',
        '{"type":"approval_done","id":"a2","ok":false,"by":"voice","later":true}\n',
        '{"type":"model","model":"ornith"}\n{"type":"model"}\n',
        '{"type":"done"}\n',
      ]
      return new Response(new ReadableStream({ start(c) { for (const p of pieces) c.enqueue(new TextEncoder().encode(p)); c.close() } }))
    }
    if (url === `${config.jarvisApiUrl}/approve`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      const { id } = JSON.parse(String(init?.body))
      if (id === 'voiced') return Response.json({ error: 'that approval is already answered no (voice)', gone: true, answer: { ok: false, by: 'voice' } }, { status: 404 })
      return Response.json({ ok: true }, { status: id === 'a1' ? jarvisStatusCode : 404 })
    }
    if (url === `${config.jarvisApiUrl}/approvals`) {
      return Response.json({ pending: [{ id: 'a2', tool: 'edit_file', summary: '~/x.md', expires: 'z' }, { tool: 'broken' }] })
    }
    if (url === `${config.jarvisApiUrl}/chat/history?limit=20&before=7`) {
      return Response.json({ turns: [{ role: 'user', text: 'earlier', at: '0', id: 5 }], has_more: true, pending: true })
    }
    if (url === `${config.jarvisApiUrl}/chat/history?limit=50`) {
      return Response.json({ turns: [{ role: 'user', text: 'lamp off', at: 'a' }, { role: 'assistant', text: 'Lamp is off.', at: 'b', model: 'claude', id: 7 }, { role: 'assistant', text: 'Leave by 7:05.', at: 'c', model: 'notice:lookout', writer: 'claude-opus-5-5', id: 8 }, { role: 'user' }] })
    }
    if (url === `${config.jarvisApiUrl}/ask`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return new Response(JSON.stringify({ reply: 'Lamp is off.' }), { status: jarvisStatusCode })
    }
    if (url.endsWith('/api/') && url.startsWith(config.haUrl)) return new Response('{}', { status: haStatusCode })
    return new Response('ok')
  })
  const execFile = vi.fn(async (cmd: string) => {
    if (cmd === config.nvidiaSmi) {
      if (gpuFails) throw new Error('nvidia-smi not found')
      return { stdout: '10342, 12288, 37\n' }
    }
    if (unitState === 'active') return { stdout: 'active\n' }
    // No systemctl at all, as in Docker.
    if (unitState === '') throw Object.assign(new Error('spawn systemctl ENOENT'), { code: 'ENOENT' })
    // systemctl exits non-zero for anything but active.
    throw Object.assign(new Error('exit 3'), { stdout: `${unitState}\n` })
  })
  const statfs = async () => ({ bavail: 93 * GB, bsize: 1, blocks: 237 * GB })
  return { source: createLiveSource(config, { fetch, execFile, statfs, restartWaitMs: 0 }), fetch }
}

/** Finds a service row by id. */
function service(snap: any, id: string) {
  return snap.services.find((s: { id: string }) => s.id === id)
}

describe('live snapshot', () => {
  it('lists only the services still on the PC (Open WebUI was removed) and never probes it', async () => {
    const { source, fetch } = liveWith({})
    const snap = await source.snapshot()
    expect(snap.services.map((s: { id: string }) => s.id)).toEqual(['ha', 'ollama', 'jarvis'])
    expect(fetch.mock.calls.some(([url]) => String(url).includes(':8081'))).toBe(false)
  })

  it("puts Jarvis's reminders for today on the timeline, past ones done", async () => {
    const past = new Date(Date.now() - 3600_000).toISOString()
    const later = new Date(Date.now() + 3600_000).toISOString()
    const schedule = { items: [
      { id: 'r1', kind: 'reminder', text: 'Call Noah about guitar', at: later },
      { id: 'p1', kind: 'pickups', text: 'Fantasy pickups', at: past },
      { id: 'bad', kind: 'reminder', text: 'No time', at: 'soon' },
    ] }
    const snap = await liveWith({ schedule }).source.snapshot()
    expect(snap.today).toEqual([
      { id: 'jarvis-r1', at: later, title: 'Call Noah about guitar', detail: 'Jarvis reminder', status: 'scheduled' },
      { id: 'jarvis-p1', at: past, title: 'Fantasy pickups', detail: 'Jarvis: fantasy pickups', status: 'done' },
    ])
  })

  it('reads what Jarvis is doing from /jobs, or null on an older Jarvis', async () => {
    const jobs = { jobs: [{ id: 'lookout', name: 'Lookout', status: 'ok' }], messenger: { sent_today: 0, cap: 5 } }
    const snap = await liveWith({ jobs }).source.snapshot()
    expect(snap.jobs?.jobs[0]).toMatchObject({ id: 'lookout', name: 'Lookout', group: 'main' })
    expect(snap.jobs?.messenger).toEqual({ sentToday: 0, cap: 5, quiet: null })
    const old = await liveWith({}).source.snapshot()
    expect(old.jobs).toBeNull()
  })

  it('has an empty timeline when Jarvis has no schedule endpoint yet', async () => {
    expect((await liveWith({}).source.snapshot()).today).toEqual([])
  })

  it('reads GPU and disk', async () => {
    const snap = await liveWith({}).source.snapshot()
    const gpu = snap.metrics.find((m: { id: string }) => m.id === 'gpu')!
    const disk = snap.metrics.find((m: { id: string }) => m.id === 'disk')!
    expect(gpu.value).toBe(10.1)
    expect(gpu.total).toBe(12)
    expect(disk.value).toBe(93)
  })

  it('names who holds the graphics card: Ollama models, Jarvis\'s loaded speech models, and the rest', async () => {
    const models = [{ name: 'ornith-1.5:9b', size_vram: 6580 * 1024 ** 2 }]
    const snap = await liveWith({ ollamaModels: models, jarvisVersion: { build: 54 } }).source.snapshot()
    expect(snap.gpu).toEqual({
      totalMb: 12288,
      usedMb: 10342,
      utilization: 37,
      users: [
        { name: 'Ornith', role: 'Local brain', mb: 6580, kind: 'local' },
        { name: 'Parakeet', role: 'Hears you', mb: 2430, kind: 'speech' },
        { name: 'Kokoro', role: 'His voice', mb: 900, kind: 'speech' },
        { name: 'Everything else', role: 'Windows, the desktop and drivers', mb: 432, kind: 'other' },
      ],
    })
    // An older Jarvis has no /gpu: his models fall into the unnamed rest.
    const older = await liveWith({ ollamaModels: models }).source.snapshot()
    expect(older.gpu?.users.map((user: { name: string }) => user.name)).toEqual(['Ornith', 'Everything else'])
    expect((await liveWith({ gpuFails: true }).source.snapshot()).gpu).toBeNull()
  })

  it('shows "Not reporting" data (null) when nvidia-smi fails, without failing the snapshot', async () => {
    const snap = await liveWith({ gpuFails: true }).source.snapshot()
    expect(snap.metrics.find((m: { id: string }) => m.id === 'gpu')!.value).toBeNull()
  })

  it('Jarvis: up with its brain when /health answers, degraded when only systemd says active, else down', async () => {
    const up = service(await liveWith({}).source.snapshot(), 'jarvis')
    expect(up.status).toBe('up')
    expect(up.detail).toBe('Thinking with claude')
    // A Jarvis that reports its build (2026-11-16) shows it after the brain, with what's staged.
    const versioned = { build: 142, hash: '7079a90abcdef', dirty: false, started_at: 'x', pending: null }
    expect(service(await liveWith({ jarvisVersion: versioned }).source.snapshot(), 'jarvis').detail).toBe('Thinking with claude · build 142')
    const staged = { ...versioned, dirty: true, pending: { build: 143, hash: '9c1e2f0abc', summary: 'memory tidy' } }
    expect(service(await liveWith({ jarvisVersion: staged }).source.snapshot(), 'jarvis').detail).toBe('Thinking with claude · build 142 with unsaved edits, pending build 143')
    expect(service(await liveWith({ jarvisAnswers: false }).source.snapshot(), 'jarvis').status).toBe('degraded')
    const down = service(await liveWith({ jarvisAnswers: false, unitState: 'failed' }).source.snapshot(), 'jarvis')
    expect(down.status).toBe('down')
    expect(down.detail).toBe('systemd says failed')
  })

  it('Jarvis in Docker (no systemctl): /health alone decides', async () => {
    const { source } = liveWith({ jarvisAnswers: false, unitState: '' })
    const jarvis = service(await source.snapshot(), 'jarvis')
    expect(jarvis.status).toBe('down')
    expect(jarvis.detail).toBe('Not answering')
  })

  it('Ollama: idle with nothing loaded, up with the local model loaded', async () => {
    expect(service(await liveWith({}).source.snapshot(), 'ollama').status).toBe('idle')
    const snap = await liveWith({ ollamaModels: [{ name: 'ornith-1.5:9b', size_vram: 6 * GB }] }).source.snapshot()
    expect(service(snap, 'ollama').status).toBe('up')
    expect(snap.model).toMatchObject({ name: 'ornith-1.5:9b', loaded: true, vramGb: 6 })
  })

  it('keeps the model card on OLLAMA_MODEL and lists every loaded model with its job', async () => {
    const soon = new Date(Date.now() + 52 * 60_000).toISOString()
    const snap = await liveWith({ ollamaModels: [
      { name: 'ornith-1.5:9b', size_vram: 5.3 * GB, expires_at: soon, context_length: 8192, details: { parameter_size: '9.7B', quantization_level: 'Q4_K_M' } },
      { name: 'llama3:8b', size_vram: 4 * GB, expires_at: '2318-01-01T00:00:00Z' },
    ] }).source.snapshot()
    expect(snap.model).toMatchObject({ name: 'ornith-1.5:9b', loaded: true, vramGb: 5.3 })
    expect(service(snap, 'ollama')).toMatchObject({ status: 'up', detail: 'ornith-1.5:9b and llama3:8b loaded' })
    expect(snap.models).toEqual([
      { name: 'ornith-1.5:9b', role: 'watch', vramGb: 5.3, until: soon, parameters: '9.7B', quantization: 'Q4_K_M', contextLength: 8192 },
      { name: 'llama3:8b', role: 'other', vramGb: 4, until: null, parameters: null, quantization: null, contextLength: null },
    ])
  })

  it('sends the HA token as a bearer header', async () => {
    const { source, fetch } = liveWith({})
    await source.snapshot()
    const haCall = fetch.mock.calls.find((c: any[]) => String(c[0]).endsWith('/api/'))!
    expect((haCall[1] as any).headers.Authorization).toBe('Bearer token')
  })
})

describe('live status rules', () => {
  it('Jarvis /health answering 502 while systemd says active is degraded', async () => {
    expect(service(await liveWith({ jarvisStatusCode: 502 }).source.snapshot(), 'jarvis').status).toBe('degraded')
  })

  it('Home Assistant rejecting the token needs attention, with the reason', async () => {
    const ha = service(await liveWith({ haStatusCode: 401 }).source.snapshot(), 'ha')
    expect(ha.status).toBe('degraded')
    expect(ha.detail).toBe('Token rejected')
  })
})

describe('live actions', () => {
  it('loads the local model for 10 idle minutes by default, like Jarvis does', async () => {
    const { source, fetch } = liveWith({})
    await source.action('ollama-load')
    const [, init] = fetch.mock.calls.at(-1)!
    expect(JSON.parse(String(init!.body))).toEqual({ model: 'ornith-1.5:9b', keep_alive: '10m' })
  })

  it('unloads with keep_alive 0', async () => {
    const { source, fetch } = liveWith({})
    const result = await source.action('ollama-unload')
    expect(result.ok).toBe(true)
    const [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toBe('http://127.0.0.1:11434/api/generate')
    expect(JSON.parse(String(init!.body))).toEqual({ model: 'ornith-1.5:9b', keep_alive: 0 })
  })
})

describe('live ask', () => {
  it('forwards the question and the Tailscale login to Jarvis /ask', async () => {
    const { source, fetch } = liveWith({})
    const result = await source.ask('lamp off', { login: 'dylan@example.com' })
    expect(result).toEqual({ ok: true, message: 'Lamp is off.' })
    const [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toBe('http://127.0.0.1:8765/ask')
    expect(JSON.parse(String(init!.body))).toEqual({ text: 'lamp off' })
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
  })

  it("doesn't call Jarvis without a Tailscale login", async () => {
    const { source, fetch } = liveWith({})
    const result = await source.ask('lamp off', {})
    expect(result.ok).toBe(false)
    expect(result.message).toBe('Open this page through Tailscale to talk to Jarvis')
    expect(fetch).not.toHaveBeenCalled()
  })

  it('says who Jarvis refused, and when it is down', async () => {
    expect((await liveWith({ jarvisStatusCode: 401 }).source.ask('hi', { login: 'x@y.z' })).message).toBe("Jarvis doesn't know x@y.z")
    expect((await liveWith({ jarvisAnswers: false }).source.ask('hi', { login: 'x@y.z' })).message).toBe('Jarvis is not answering')
  })
})

describe('parseKeepAlive', () => {
  it('turns whole numbers into numbers and leaves durations alone', () => {
    expect(parseKeepAlive('-1')).toBe(-1)
    expect(parseKeepAlive('3600')).toBe(3600)
    expect(parseKeepAlive('30m')).toBe('30m')
  })
})

describe('digest refresh', () => {
  it("asks Jarvis as the caller and passes on whether it's running", async () => {
    const { source, fetch } = liveWith({})
    expect(await source.refreshDigest({ login: 'dylan@example.com' })).toEqual({ running: true, lastWrite: '2026-11-10T09:16:11Z' })
    const [, init] = fetch.mock.calls.find(([url]) => url.endsWith('/digest/refresh'))!
    expect(init!.method).toBe('POST')
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
  })

  it('reads as not running without a login, when Jarvis is down, or on an older Jarvis', async () => {
    const idle = { running: false, lastWrite: null }
    expect(await liveWith({}).source.refreshDigest({})).toEqual(idle)
    expect(await liveWith({ jarvisAnswers: false }).source.refreshDigest({ login: 'd' })).toEqual(idle)
    expect(await liveWith({ jarvisStatusCode: 404 }).source.refreshDigest({ login: 'd' })).toEqual(idle)
  })
})

describe('live chat with Jarvis', () => {
  it('passes streamed pieces on as they arrive, joining lines split across chunks', async () => {
    const { source, fetch } = liveWith({})
    const events: unknown[] = []
    await source.chat('lamp off', { login: 'dylan@example.com' }, (e: unknown) => events.push(e))
    expect(events).toEqual([
      { type: 'delta', text: 'Lamp ' },
      { type: 'delta', text: 'is off.' },
      { type: 'approval', approval: { id: 'a1', tool: 'run_command', summary: 'ls', expires: '2026-11-11T12:20:00Z' } },
      { type: 'approval_done', id: 'a1', ok: true, by: 'voice', later: false },
      { type: 'approval_done', id: 'a2', ok: false, by: 'voice', later: true },
      { type: 'model', model: 'ornith' },
      { type: 'done', ok: true },
    ])
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/chat/stream`)!
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
  })

  it('answers approvals and lists the waiting ones, as the caller', async () => {
    const { source, fetch } = liveWith({})
    const login = { login: 'dylan@example.com' }
    expect(await source.answerApproval('a1', true, login)).toEqual({ ok: true, message: 'Approved' })
    // Already over: `gone` tells the page to drop the card, with how it was answered when Jarvis remembers.
    expect(await source.answerApproval('gone', false, login)).toEqual({ ok: false, gone: true, message: 'That request was already answered or ran out of time' })
    expect(await source.answerApproval('voiced', false, login)).toEqual({ ok: false, gone: true, message: 'That approval is already answered no (voice)', answer: { ok: false, by: 'voice', later: false } })
    expect(await source.approvals(login)).toEqual([{ id: 'a2', tool: 'edit_file', summary: '~/x.md', expires: 'z' }])
    expect(await source.answerApproval('a1', true, {})).toMatchObject({ ok: false })
    expect(await liveWith({ jarvisAnswers: false }).source.answerApproval('a1', true, login)).toEqual({ ok: false, message: 'Jarvis is not answering' })
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/approve`)!
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
  })

  it('says why when there is no login, Jarvis is down, or refuses the caller', async () => {
    const events: unknown[] = []
    await liveWith({}).source.chat('hi', {}, (e: unknown) => events.push(e))
    await liveWith({ jarvisAnswers: false }).source.chat('hi', { login: 'x@y.z' }, (e: unknown) => events.push(e))
    await liveWith({ jarvisStatusCode: 401 }).source.chat('hi', { login: 'x@y.z' }, (e: unknown) => events.push(e))
    expect(events).toEqual([
      { type: 'error', message: 'Open this page through Tailscale to talk to Jarvis' },
      { type: 'error', message: 'Jarvis is not answering' },
      { type: 'error', message: "Jarvis doesn't know x@y.z" },
    ])
  })

  it('says Jarvis is restarting in plain words, and sends a chat message once more when he was', async () => {
    expect(jarvisSaid(502)).toBe('Jarvis is restarting. Try again in a moment.')
    expect(jarvisSaid(500)).toBe('Jarvis answered 500')
    // Down for the first try, back for the second: the reply comes through with no error shown.
    let tries = 0
    const fetch = vi.fn(async () => {
      tries += 1
      if (tries === 1) return new Response('bad gateway', { status: 502 })
      return new Response('{"type":"delta","text":"Hi."}\n{"type":"done"}\n')
    })
    const source = createLiveSource(config, { fetch, execFile: vi.fn(), statfs: vi.fn(), restartWaitMs: 0 })
    const events: unknown[] = []
    await source.chat('hello', { login: 'dylan@example.com' }, (e: unknown) => events.push(e))
    expect(events).toEqual([{ type: 'delta', text: 'Hi.' }, { type: 'done', ok: true }])
    expect(tries).toBe(2)
    // Still down on the second try: one plain message, and no third try.
    const down = vi.fn(async () => new Response('bad gateway', { status: 503 }))
    const stuck: unknown[] = []
    await createLiveSource(config, { fetch: down, execFile: vi.fn(), statfs: vi.fn(), restartWaitMs: 0 }).chat('hello', { login: 'dylan@example.com' }, (e: unknown) => stuck.push(e))
    expect(stuck).toEqual([{ type: 'error', message: 'Jarvis is restarting. Try again in a moment.' }])
    expect(down).toHaveBeenCalledTimes(2)
  })

  it('tells Jarvis the asker left, with the turn id when it has one, as the caller', async () => {
    const { source, fetch } = liveWith({})
    await source.chatLeft(41, { login: 'dylan@example.com' })
    await source.chatLeft(null, { login: 'dylan@example.com' })
    const calls = fetch.mock.calls.filter((c) => c[0] === `${config.jarvisApiUrl}/chat/left`)
    expect(calls.map(([, init]) => [(init!.headers as Record<string, string>)['tailscale-user-login'], init!.body])).toEqual([['dylan@example.com', '{"turn_id":41}'], ['dylan@example.com', '{}']])
    // No login, nobody to speak for: nothing is sent.
    await source.chatLeft(41, {})
    expect(fetch.mock.calls.filter((c) => c[0] === `${config.jarvisApiUrl}/chat/left`)).toHaveLength(2)
  })

  it("reads the web chat history, naming Jarvis's lines and dropping broken ones", async () => {
    const { turns, hasMore, hasNewer, pending } = await liveWith({}).source.history({ login: 'dylan@example.com' })
    expect([hasMore, hasNewer, pending]).toEqual([false, false, false])
    expect(turns).toEqual([{ role: 'user', text: 'lamp off', at: 'a' }, { role: 'jarvis', text: 'Lamp is off.', at: 'b', model: 'claude', id: 7 }, { role: 'jarvis', text: 'Leave by 7:05.', at: 'c', model: 'notice:lookout', writer: 'claude-opus-5-5', id: 8 }])
    expect(await liveWith({}).source.history({})).toEqual({ turns: [], hasMore: false, hasNewer: false, pending: false })
  })

  it('asks Jarvis for the turns before one, and says when older ones exist or a reply is still being written', async () => {
    const page = await liveWith({}).source.history({ login: 'dylan@example.com' }, { limit: 20, before: 7 })
    expect(page).toEqual({ turns: [{ role: 'user', text: 'earlier', at: '0', id: 5 }], hasMore: true, hasNewer: false, pending: true })
  })

  it("reads and saves Jarvis's voice and fetches samples as the caller", async () => {
    const { source, fetch } = liveWith({})
    const login = { login: 'dylan@example.com' }
    expect(await source.voice(login)).toEqual({
      voice: 'bm_george', speed: 1.1, blend: null,
      voices: [{ id: 'bm_george', name: 'George', accent: 'gb', gender: 'm' }, { id: 'af_heart', name: 'af_heart', accent: 'us', gender: 'm' }],
    })
    const choice = { voice: 'bm_lewis', speed: 1, blend: { voice2: 'bm_george', mix: 0.3 } }
    expect(await source.setVoice(choice, login)).toEqual({ ok: true, message: 'Saved' })
    const sample = await source.voiceSample(choice, login)
    expect(Array.from(sample.audio ?? [])).toEqual([82, 73, 70, 70])
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/voice/sample?voice=bm_lewis&speed=1&voice2=bm_george&mix=0.3'))).toBe(true)
    expect(await source.voice({})).toBeNull()
    expect((await source.setVoice(choice, {})).ok).toBe(false)
    expect((await source.voiceSample(choice, {})).ok).toBe(false)
    expect(await liveWith({ jarvisAnswers: false }).source.voice(login)).toBeNull()
  })

  it("reads, searches and changes Jarvis's memory as the caller, dropping broken rows", async () => {
    const { source, fetch } = liveWith({})
    const login = { login: 'dylan@example.com' }
    expect(await source.memory(login)).toEqual({ facts: [{ id: 'a', text: 'Likes knots', learned: '2026-11-10T11:30:00Z', from: 'nightly' }], turns: 42, lastDistill: '2026-11-11T11:30:00Z' })
    expect(await source.searchMemory('lamp off', login)).toEqual([{ chat: 'voice', role: 'jarvis', text: 'Lamp is off.', at: 'b' }])
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/memory/search?q=lamp%20off&limit=8'))).toBe(true)
    expect(await source.changeMemory({ op: 'forget', id: 'a' }, login)).toEqual({ ok: true, message: 'Forgotten' })
    expect(await source.memory({})).toBeNull()
    expect(await source.searchMemory('x', {})).toEqual([])
    expect((await source.changeMemory({ op: 'forget', id: 'a' }, {})).ok).toBe(false)
    expect(await liveWith({ jarvisAnswers: false }).source.memory(login)).toBeNull()
  })

  it('reads a day and a week of the meal log as the caller, null without a login or when Jarvis is down', async () => {
    const { source, fetch } = liveWith({})
    const login = { login: 'dylan@example.com' }
    const day = await source.nutritionDay('2026-11-17', login)
    expect(day?.items).toEqual([{ id: '4', at: '2026-11-17T08:00:00-08:00', name: 'Latte', portion: null, calories: 250, protein: null, fat: null, carbs: null, hasPhoto: true }])
    expect(day?.totals.burned).toBe(300)
    const call = fetch.mock.calls.find((c) => String(c[0]).endsWith('/nutrition/day?date=2026-11-17'))
    expect((call?.[1]?.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
    expect((await source.nutritionWeek('', login))?.days).toEqual([{ date: '2026-11-15', calories: 1600, goal: 1750, protein: 120.3, proteinGoal: 140, fat: null, fatGoal: null, carbs: null, carbsGoal: null }])
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/nutrition/week'))).toBe(true)
    const thumb = await source.mealPhoto('4', true, login)
    expect(thumb).toEqual({ ok: true, type: 'image/jpeg', bytes: new Uint8Array([1, 2, 3]) })
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/nutrition/photo/4?size=thumb'))).toBe(true)
    expect(await source.mealPhoto('9', false, login)).toMatchObject({ ok: false, gone: true })
    expect((await source.mealPhoto('4', false, {})).ok).toBe(false)
    expect(await liveWith({ jarvisAnswers: false }).source.mealPhoto('4', false, login)).toEqual({ ok: false, message: 'Jarvis is not answering' })
    const run = await source.nutritionDays('2026-11-17', 2, login)
    expect(run?.days.map((d: { date: string }) => d.date)).toEqual(['2026-11-17', '2026-11-16'])
    expect(run?.earliest).toBe('2026-10-02')
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/nutrition/days?count=2&end=2026-11-17'))).toBe(true)
    expect(await source.nutritionDays('', 7, {})).toBeNull()
    expect(await liveWith({ jarvisStatusCode: 404 }).source.nutritionDays('', 7, login)).toBeNull()
    expect(await source.nutritionDay('2026-11-17', {})).toBeNull()
    expect(await source.nutritionWeek('', {})).toBeNull()
    expect(await liveWith({ jarvisAnswers: false }).source.nutritionDay('', login)).toBeNull()
    expect(await liveWith({ jarvisStatusCode: 404 }).source.nutritionDay('', login)).toBeNull()
  })

  it('reads and stores nights of sleep as the caller, and puts the latest in the snapshot', async () => {
    const { source, fetch } = liveWith({})
    const login = { login: 'dylan@example.com' }
    const nights = await source.sleepNights({ night: '', days: 7 }, login)
    expect(nights?.map((night: { night: string }) => night.night)).toEqual(['2026-11-18', '2026-11-17'])
    expect(nights?.[0]).toMatchObject({ score: 72, scoreBand: 'good' })
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/health/sleep?days=7') && (c[1]?.headers as Record<string, string>)?.['tailscale-user-login'] === 'dylan@example.com')).toBe(true)
    await source.sleepNights({ night: '2026-11-18', days: 7 }, login)
    expect(fetch.mock.calls.some((c) => String(c[0]).endsWith('/health/sleep?night=2026-11-18'))).toBe(true)
    expect(await source.sleepNights({ night: '', days: 7 }, {})).toBeNull()
    expect(await liveWith({ jarvisStatusCode: 404 }).source.sleepNights({ night: '', days: 7 }, login)).toBeNull()

    const saved = await source.saveSleepNight({ night: '2026-11-18', stages: [] }, login)
    expect(saved).toMatchObject({ ok: true, message: 'Saved', night: { night: '2026-11-18', score: 72 } })
    expect(await source.saveSleepNight({ night: '2026-01-01', stages: [] }, login)).toEqual({ ok: false, refused: true, message: 'night is too old' })
    expect((await source.saveSleepNight({ night: '2026-11-18' }, {})).ok).toBe(false)
    expect(await liveWith({ jarvisStatusCode: 404 }).source.saveSleepNight({ night: '2026-11-18' }, login)).toEqual({ ok: false, message: 'Jarvis can’t take sleep details yet' })
    expect(await liveWith({ jarvisAnswers: false }).source.saveSleepNight({ night: '2026-11-18' }, login)).toEqual({ ok: false, message: 'Jarvis is not answering' })

    const snapshot = await source.snapshot()
    expect(snapshot.sleep?.last).toMatchObject({ night: '2026-11-18', score: 72 })
    expect(snapshot.sleep?.last).not.toHaveProperty('stages')
    expect(snapshot.sleep?.trend).toEqual([{ night: '2026-11-18', score: 72, asleep: 400 }, { night: '2026-11-17', score: 60, asleep: 380 }])
    expect((await liveWith({ jarvisAnswers: false }).source.snapshot()).sleep).toBeNull()
  })

  it('puts who holds the memory and the disks in the snapshot, null on an older Jarvis', async () => {
    const snapshot = await liveWith({}).source.snapshot()
    expect(snapshot.ram).toMatchObject({ totalMb: 32000, usedMb: 9000, scope: 'pc', users: [{ name: 'Jarvis', role: 'The agent', mb: 2100 }, { name: 'Everything else', mb: 6900 }] })
    expect(snapshot.disks).toEqual([{ id: 'c', name: 'C: drive', usedGb: 200, totalGb: 238, users: [{ name: 'Everything else', gb: 200 }] }])
    const older = await liveWith({ jarvisStatusCode: 404 }).source.snapshot()
    expect(older.ram).toBeNull()
    expect(older.disks).toBeNull()
  })

  it("warms Jarvis's chat engine as the caller, and skips it without a login", async () => {
    const { source, fetch } = liveWith({})
    expect(await source.warm({ login: 'dylan@example.com' })).toBe(true)
    const [url, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/chat/warm`)!
    expect(url).toContain('/chat/warm')
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
    expect(await source.warm({})).toBe(false)
    expect(await liveWith({ jarvisAnswers: false }).source.warm({ login: 'dylan@example.com' })).toBe(false)
  })

  it('tells Jarvis you have gone to bed, and says so plainly when it cannot', async () => {
    const { source, fetch } = liveWith({})
    expect(await source.setSleep(true, 'tv', { login: 'dylan@example.com' })).toEqual({ ok: true, message: 'Good night' })
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/sleep`)!
    expect(JSON.parse(init!.body as string)).toEqual({ asleep: true, source: 'tv' })
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
    expect((await source.setSleep(true, 'tv', {})).ok).toBe(false)
    expect((await liveWith({ jarvisStatusCode: 404 }).source.setSleep(true, 'tv', { login: 'd@example.com' })).message).toBe('Jarvis can’t track sleep yet')
    expect((await liveWith({ jarvisAnswers: false }).source.setSleep(false, 'tv', { login: 'd@example.com' })).message).toBe('Jarvis is not answering')
  })

  it('keeps a chat message or a notice with Jarvis and lets it go', async () => {
    const { source, fetch } = liveWith({})
    const who = { login: 'dylan@example.com' }
    expect(await source.keepNotice({ turnId: 7 }, who)).toEqual({
      ok: true,
      message: 'Kept',
      notice: { id: 'k7', kind: 'fyi', title: 'Call the shop', body: '', source: 'kept', created: null, turnId: 7, kept: true },
    })
    await source.keepNotice({ id: 'n1' }, who)
    const sent = fetch.mock.calls.filter((c) => c[0] === `${config.jarvisApiUrl}/notices/keep`).map((c) => JSON.parse(c[1]!.body as string))
    expect(sent).toEqual([{ turn_id: 7 }, { notice_id: 'n1' }])
    expect((await source.keepNotice({ turnId: 99 }, who)).message).toBe('Jarvis can’t find that message')
    expect((await source.keepNotice({ turnId: 7 }, {})).ok).toBe(false)
    expect(await source.unkeepNotice('k7', who)).toEqual({ ok: true, message: 'Let go' })
    const [, gone] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/notices/unkeep`)!
    expect(JSON.parse(gone!.body as string)).toEqual({ id: 'k7' })
    const old = liveWith({ jarvisStatusCode: 404 }).source
    expect((await old.keepNotice({ turnId: 7 }, who)).message).toBe('Jarvis can’t keep messages yet')
    expect((await old.unkeepNotice('k7', who)).message).toBe('Jarvis can’t keep messages yet')
    expect((await liveWith({ jarvisAnswers: false }).source.keepNotice({ id: 'n1' }, who)).message).toBe('Jarvis is not answering')
  })

  it('puts Jarvis’s notices in the snapshot, clears them and registers a device for pushes', async () => {
    const { source, fetch } = liveWith({})
    expect((await source.snapshot()).notices).toEqual([{ id: 'n1', kind: 'heads', title: 'Rain at 4', body: '', source: 'lookout', created: null }])
    expect(await source.clearNotices({ ids: ['n1'] }, { login: 'dylan@example.com' })).toEqual({ ok: true, message: 'Cleared' })
    const [, cleared] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/notices/clear`)!
    expect(JSON.parse(cleared!.body as string)).toEqual({ ids: ['n1'] })
    const device = { token: 'ab'.repeat(32), platform: 'ios' as const, environment: 'sandbox' as const, bundle: 'com.example.app', name: 'iPhone' }
    expect(await source.registerPush(device, { login: 'dylan@example.com' })).toEqual({ ok: true, message: 'Registered' })
    const [, registered] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/push/register`)!
    expect(JSON.parse(registered!.body as string)).toEqual(device)
    expect((await source.clearNotices({ all: true }, {})).ok).toBe(false)
    const old = liveWith({ jarvisStatusCode: 404 }).source
    expect((await old.snapshot()).notices).toBeNull()
    expect((await old.registerPush(device, { login: 'd@example.com' })).message).toBe('Jarvis can’t send notifications yet')
    expect((await liveWith({ jarvisAnswers: false }).source.clearNotices({ all: true }, { login: 'd@example.com' })).message).toBe('Jarvis is not answering')
  })

  it('puts today’s calories in the snapshot, working out what is left itself', async () => {
    const snapshot = await liveWith({}).source.snapshot()
    expect(snapshot.nutrition).toEqual({ date: '2026-11-18', eaten: 1200, goal: 1750, left: 550, burned: null, protein: 90, proteinGoal: 140, fat: null, fatGoal: null, carbs: null, carbsGoal: null })
  })

  it('sends a chat message’s photos to Jarvis as media_type and data', async () => {
    const { source, fetch } = liveWith({})
    await source.chat('lunch', { login: 'dylan@example.com', images: [{ type: 'image/jpeg', data: 'aGVsbG8=' }] }, () => {})
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/chat/stream`)!
    expect(JSON.parse(init!.body as string)).toEqual({ text: 'lunch', images: [{ media_type: 'image/jpeg', data: 'aGVsbG8=' }] })
  })

  it('stops a background job, passing on what Jarvis said', async () => {
    const who = { login: 'dylan@example.com' }
    const { source, fetch } = liveWith({})
    expect(await source.stopJob('r1', who)).toEqual({ ok: true, message: 'Stopped "Shorter greeting" and put things back as they were.' })
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/jobs/r1/stop`)!
    expect(init!.method).toBe('POST')
    expect((init!.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
    expect(await source.stopJob('done', who)).toEqual({ ok: false, gone: true, message: 'That job already finished.' })
    expect(await source.stopJob('live', who)).toEqual({ ok: false, message: 'It\'s going live right now.' })
    expect((await source.stopJob('r1', {})).ok).toBe(false)
    // An older Jarvis has no such path: the row is dropped all the same.
    expect((await liveWith({ jarvisStatusCode: 404 }).source.stopJob('r1', who)).gone).toBe(true)
    expect((await liveWith({ jarvisStatusCode: 503 }).source.stopJob('r1', who)).message).toBe('Jarvis is restarting. Try again in a moment.')
    expect((await liveWith({ jarvisAnswers: false }).source.stopJob('r1', who)).message).toBe('Jarvis is not answering')
  })
})
