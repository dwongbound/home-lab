// The live source with every probe faked: status rules, failures that
// shouldn't break the page, and the Ollama load/unload call.
import { describe, expect, it, vi } from 'vitest'
import { createLiveSource, parseKeepAlive } from '../../server/sources/live.mjs'
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
}

/** A live source whose fetch/execFile/statfs answer as described. */
function liveWith({ ollamaModels = [], jarvisAnswers = true, jarvisStatusCode = 200, haStatusCode = 200, unitState = 'active', gpuFails = false, schedule }: Fakes) {
  const fetch = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.endsWith('/api/ps')) return new Response(JSON.stringify({ models: ollamaModels }))
    if (url === `${config.jarvisApiUrl}/health`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return new Response(JSON.stringify({ ok: true, brain: 'claude' }), { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/schedule/today`) {
      if (schedule === undefined) return new Response('not found', { status: 404 })
      return Response.json(schedule)
    }
    if (url === `${config.jarvisApiUrl}/digest/refresh`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return Response.json({ running: true, lastWrite: '2026-11-10T09:16:11Z' }, { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/chat/stream`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      if (jarvisStatusCode !== 200) return new Response('no', { status: jarvisStatusCode })
      // Split mid-line on purpose: the reader must join pieces before parsing.
      const pieces = ['{"type":"delta","text":"Lamp "}\n{"type":"del', 'ta","text":"is off."}\n', '{"type":"done"}\n']
      return new Response(new ReadableStream({ start(c) { for (const p of pieces) c.enqueue(new TextEncoder().encode(p)); c.close() } }))
    }
    if (url === `${config.jarvisApiUrl}/chat/history?limit=50`) {
      return Response.json({ turns: [{ role: 'user', text: 'lamp off', at: 'a' }, { role: 'assistant', text: 'Lamp is off.', at: 'b' }, { role: 'user' }] })
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
      return { stdout: '10342, 12288\n' }
    }
    if (unitState === 'active') return { stdout: 'active\n' }
    // No systemctl at all, as in Docker.
    if (unitState === '') throw Object.assign(new Error('spawn systemctl ENOENT'), { code: 'ENOENT' })
    // systemctl exits non-zero for anything but active.
    throw Object.assign(new Error('exit 3'), { stdout: `${unitState}\n` })
  })
  const statfs = async () => ({ bavail: 93 * GB, bsize: 1, blocks: 237 * GB })
  return { source: createLiveSource(config, { fetch, execFile, statfs }), fetch }
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

  it('shows "Not reporting" data (null) when nvidia-smi fails, without failing the snapshot', async () => {
    const snap = await liveWith({ gpuFails: true }).source.snapshot()
    expect(snap.metrics.find((m: { id: string }) => m.id === 'gpu')!.value).toBeNull()
  })

  it('Jarvis: up with its brain when /health answers, degraded when only systemd says active, else down', async () => {
    const up = service(await liveWith({}).source.snapshot(), 'jarvis')
    expect(up.status).toBe('up')
    expect(up.detail).toBe('Thinking with claude')
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

  it('Ollama: idle with nothing loaded, up with Gemma loaded', async () => {
    expect(service(await liveWith({}).source.snapshot(), 'ollama').status).toBe('idle')
    const snap = await liveWith({ ollamaModels: [{ name: 'gemma4:12b', size_vram: 10 * GB }] }).source.snapshot()
    expect(service(snap, 'ollama').status).toBe('up')
    expect(snap.model).toMatchObject({ loaded: true, vramGb: 10 })
  })

  it('keeps the Gemma card on Gemma and lists every loaded model with its job', async () => {
    const soon = new Date(Date.now() + 52 * 60_000).toISOString()
    const snap = await liveWith({ ollamaModels: [
      { name: 'qwen3.5:9b', size_vram: 5.3 * GB, expires_at: soon, context_length: 8192, details: { parameter_size: '9.7B', quantization_level: 'Q4_K_M' } },
      { name: 'llama3:8b', size_vram: 4 * GB, expires_at: '2318-01-01T00:00:00Z' },
    ] }).source.snapshot()
    expect(snap.model).toMatchObject({ name: 'gemma4:12b', loaded: false, vramGb: 0 })
    expect(service(snap, 'ollama')).toMatchObject({ status: 'up', detail: 'qwen3.5:9b and llama3:8b loaded' })
    expect(snap.models).toEqual([
      { name: 'qwen3.5:9b', role: 'watch', vramGb: 5.3, until: soon, parameters: '9.7B', quantization: 'Q4_K_M', contextLength: 8192 },
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
  it('loads with keep_alive -1 by default, so Gemma stays loaded like it normally does', async () => {
    const { source, fetch } = liveWith({})
    await source.action('ollama-load')
    const [, init] = fetch.mock.calls.at(-1)!
    expect(JSON.parse(String(init!.body))).toEqual({ model: 'gemma4:12b', keep_alive: -1 })
  })

  it('unloads with keep_alive 0', async () => {
    const { source, fetch } = liveWith({})
    const result = await source.action('ollama-unload')
    expect(result.ok).toBe(true)
    const [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toBe('http://127.0.0.1:11434/api/generate')
    expect(JSON.parse(String(init!.body))).toEqual({ model: 'gemma4:12b', keep_alive: 0 })
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
    expect(events).toEqual([{ type: 'delta', text: 'Lamp ' }, { type: 'delta', text: 'is off.' }, { type: 'done', ok: true }])
    const [, init] = fetch.mock.calls.find((c) => c[0] === `${config.jarvisApiUrl}/chat/stream`)!
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

  it("reads the web chat history, naming Jarvis's lines and dropping broken ones", async () => {
    const turns = await liveWith({}).source.history({ login: 'dylan@example.com' })
    expect(turns).toEqual([{ role: 'user', text: 'lamp off', at: 'a' }, { role: 'jarvis', text: 'Lamp is off.', at: 'b' }])
    expect(await liveWith({}).source.history({})).toEqual([])
  })
})
