// The live source with every probe faked: status rules, failures that
// shouldn't break the page, and the Ollama load/unload call.
import { describe, expect, it, vi } from 'vitest'
import { createLiveSource, parseKeepAlive } from '../../server/sources/live.mjs'
import { loadConfig } from '../../server/config.mjs'

const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })
const GB = 1024 ** 3

/** A few entities as HA's /api/states lists them, plus one the page ignores. */
const HA_STATES = [
  { entity_id: 'light.desk', state: 'on', attributes: { friendly_name: 'Desk lamp', supported_color_modes: ['brightness'], brightness: 128 } },
  { entity_id: 'lock.front_door', state: 'unlocked', attributes: { friendly_name: 'Front door' } },
  { entity_id: 'sensor.outside_temperature', state: '61', attributes: { friendly_name: 'Outside' } },
]

interface Fakes {
  ollamaModels?: unknown[]
  jarvisAnswers?: boolean
  jarvisStatusCode?: number
  haStatusCode?: number
  unitState?: string
  gpuFails?: boolean
}

/** A live source whose fetch/execFile/statfs answer as described. */
function liveWith({ ollamaModels = [], jarvisAnswers = true, jarvisStatusCode = 200, haStatusCode = 200, unitState = 'active', gpuFails = false }: Fakes) {
  const fetch = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.endsWith('/api/ps')) return new Response(JSON.stringify({ models: ollamaModels }))
    if (url === `${config.jarvisApiUrl}/health`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return new Response(JSON.stringify({ ok: true, brain: 'claude' }), { status: jarvisStatusCode })
    }
    if (url === `${config.jarvisApiUrl}/ask`) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      return new Response(JSON.stringify({ reply: 'Lamp is off.' }), { status: jarvisStatusCode })
    }
    if (url === `${config.haUrl}/api/states`) return new Response(JSON.stringify(HA_STATES), { status: haStatusCode })
    if (url.startsWith(`${config.haUrl}/api/services/`)) return new Response('[]', { status: haStatusCode })
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

  it('sends the HA token as a bearer header', async () => {
    const { source, fetch } = liveWith({})
    await source.snapshot()
    const haCall = fetch.mock.calls.find((c: any[]) => String(c[0]).endsWith('/api/states'))!
    expect((haCall[1] as any).headers.Authorization).toBe('Bearer token')
  })
})

describe('live home', () => {
  it('lists Home Assistant devices from the same /api/states call that checks HA is up', async () => {
    const { source, fetch } = liveWith({})
    const snap = await source.snapshot()
    expect(snap.home!.map((d: { id: string }) => d.id)).toEqual(['light.desk', 'lock.front_door'])
    expect(snap.home![0]).toMatchObject({ name: 'Desk lamp', on: true, brightness: 50 })
    expect(snap.home![1]).toMatchObject({ kind: 'lock', on: false })
    const haCalls = fetch.mock.calls.filter((c: any[]) => String(c[0]).startsWith(config.haUrl))
    expect(haCalls).toHaveLength(1)
  })

  it('has no devices (null) when HA rejects the token', async () => {
    expect((await liveWith({ haStatusCode: 401 }).source.snapshot()).home).toBeNull()
  })

  it('calls the matching HA service with the token', async () => {
    const { source, fetch } = liveWith({})
    const result = await source.home({ id: 'light.desk', command: 'brightness', value: 40 })
    expect(result).toEqual({ ok: true, message: 'set to 40%' })
    const [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toBe(`${config.haUrl}/api/services/light/turn_on`)
    expect(JSON.parse(String(init!.body))).toEqual({ entity_id: 'light.desk', brightness_pct: 40 })
    expect((init!.headers as Record<string, string>).Authorization).toBe('Bearer token')
  })

  it('says when HA refuses', async () => {
    const result = await liveWith({ haStatusCode: 401 }).source.home({ id: 'lock.front_door', command: 'lock' })
    expect(result).toEqual({ ok: false, message: 'Home Assistant rejected the token' })
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
