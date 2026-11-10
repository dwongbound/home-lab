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
}

/** A live source whose fetch/execFile/statfs answer as described. */
function liveWith({ ollamaModels = [], jarvisAnswers = true, jarvisStatusCode = 404, haStatusCode = 200, unitState = 'active', gpuFails = false }: Fakes) {
  const fetch = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.endsWith('/api/ps')) return new Response(JSON.stringify({ models: ollamaModels }))
    if (url === config.jarvisUrl) {
      if (!jarvisAnswers) throw new Error('connect ECONNREFUSED')
      // The real Jarvis answers 404 at "/".
      return new Response('not found', { status: jarvisStatusCode })
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

  it('Jarvis: up, degraded when the port is silent, down when systemd says so', async () => {
    expect(service(await liveWith({}).source.snapshot(), 'jarvis').status).toBe('up')
    expect(service(await liveWith({ jarvisAnswers: false }).source.snapshot(), 'jarvis').status).toBe('degraded')
    const down = service(await liveWith({ unitState: 'failed' }).source.snapshot(), 'jarvis')
    expect(down.status).toBe('down')
    expect(down.detail).toBe('systemd says failed')
  })

  it('Jarvis in Docker (JARVIS_UNIT empty): never runs systemctl, the port decides', async () => {
    const dockerConfig = loadConfig({ DATA_SOURCE: 'live', JARVIS_UNIT: '' })
    const execFile = vi.fn(async (cmd: string) => {
      if (cmd === 'systemctl') throw new Error('systemctl: not found')
      return { stdout: '10342, 12288\n' }
    })
    const statfs = async () => ({ bavail: GB, bsize: 1, blocks: GB })
    const answering = vi.fn(async () => new Response('not found', { status: 404 }))
    const up = service(await createLiveSource(dockerConfig, { fetch: answering, execFile, statfs }).snapshot(), 'jarvis')
    expect(up).toMatchObject({ status: 'up', detail: 'Answering on its port' })
    expect(execFile).not.toHaveBeenCalledWith('systemctl', expect.anything(), expect.anything())

    const silent = vi.fn(async () => { throw new Error('connect ECONNREFUSED') })
    const down = service(await createLiveSource(dockerConfig, { fetch: silent, execFile, statfs }).snapshot(), 'jarvis')
    expect(down).toMatchObject({ status: 'down', detail: 'Not answering on its port' })
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
    const haCall = fetch.mock.calls.find((c: any[]) => String(c[0]).endsWith('/api/'))!
    expect((haCall[1] as any).headers.Authorization).toBe('Bearer token')
  })
})

describe('live status rules', () => {
  it('Jarvis answering 404 at / is up, a 502 is degraded', async () => {
    expect(service(await liveWith({ jarvisStatusCode: 404 }).source.snapshot(), 'jarvis').status).toBe('up')
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

describe('parseKeepAlive', () => {
  it('turns whole numbers into numbers and leaves durations alone', () => {
    expect(parseKeepAlive('-1')).toBe(-1)
    expect(parseKeepAlive('3600')).toBe(3600)
    expect(parseKeepAlive('30m')).toBe('30m')
  })
})
