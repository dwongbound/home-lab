// src/lib/talk.ts: the voice line's address, its audio conversions, and
// that it refuses plainly when there's no microphone, and which of
// Jarvis's events reach which handler.
import { describe, expect, it, vi } from 'vitest'
import { makeResampler, openTalkLine, pcm16ToFloat, talkUrl } from '../../src/lib/talk'

describe('the voice line', () => {
  it('uses wss on the https page and ws on plain http', () => {
    expect(talkUrl({ protocol: 'https:', host: 'jarvis.example.ts.net' })).toBe('wss://jarvis.example.ts.net/api/jarvis/talk')
    expect(talkUrl({ protocol: 'http:', host: '127.0.0.1:5180' })).toBe('ws://127.0.0.1:5180/api/jarvis/talk')
  })

  it("turns Jarvis's 16-bit voice into floats", () => {
    const bytes = new ArrayBuffer(6)
    const view = new DataView(bytes)
    view.setInt16(0, 0x4000, true)
    view.setInt16(2, -0x8000, true)
    view.setInt16(4, 0, true)
    expect(Array.from(pcm16ToFloat(bytes))).toEqual([0.5, -1, 0])
  })

  it('resamples the microphone to 16 kHz in 20 ms frames, across chunk edges', () => {
    // One second of a 440 Hz tone at 48 kHz, fed in the worklet's 128-sample chunks.
    const resample = makeResampler(48000)
    const frames: Int16Array[] = []
    for (let start = 0; start < 48000; start += 128) {
      const chunk = new Float32Array(128)
      for (let i = 0; i < 128; i++) chunk[i] = 0.5 * Math.sin((2 * Math.PI * 440 * (start + i)) / 48000)
      frames.push(...resample(chunk))
    }
    // 16000 samples a second, 320 to a frame: 50 frames (the last may still be filling).
    expect(frames.length).toBeGreaterThanOrEqual(49)
    expect(frames.every((f) => f.length === 320)).toBe(true)
    // Sample n at 16 kHz is the tone at time n/16000.
    const n = 5000
    const got = frames[Math.floor(n / 320)][n % 320] / 0x7fff
    expect(got).toBeCloseTo(0.5 * Math.sin((2 * Math.PI * 440 * n) / 16000), 2)
  })

  it('refuses in words when the browser has no microphone', async () => {
    const on = { onState: vi.fn(), onHearing: vi.fn(), onHeard: vi.fn(), onReply: vi.fn(), onDone: vi.fn(), onInterrupted: vi.fn(), onLevel: vi.fn(), onClosed: vi.fn() }
    await expect(openTalkLine('ws://x/api/jarvis/talk', on)).rejects.toThrow('This browser can’t send your voice to Jarvis')
  })

  it('hands your words over while you talk, then the whole turn, then his reply', async () => {
    // Just enough of a browser's audio and WebSocket for the line to open.
    const node = () => ({ connect: (next: unknown) => next, gain: { value: 1 }, fftSize: 0, getFloatTimeDomainData: () => {} })
    class FakeContext {
      state = 'running'
      destination = node()
      currentTime = 0
      audioWorklet = { addModule: async () => {} }
      createMediaStreamSource = node
      createAnalyser = node
      createGain = node
      close = async () => {}
    }
    class FakeWorklet { port: { onmessage: unknown } = { onmessage: null }; connect = (next: unknown) => next }
    let socket: { onopen?: () => void; onmessage?: (e: { data: string }) => void; readyState: number; send: () => void; close: () => void } | null = null
    class FakeSocket {
      static OPEN = 1
      static CONNECTING = 0
      readyState = 1
      binaryType = ''
      onopen?: () => void
      send = vi.fn()
      close = vi.fn()
      constructor() { socket = this as never }
    }
    vi.stubGlobal('AudioContext', FakeContext)
    vi.stubGlobal('AudioWorkletNode', FakeWorklet)
    vi.stubGlobal('WebSocket', FakeSocket)
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: async () => ({ getTracks: () => [] }) } })
    vi.stubGlobal('requestAnimationFrame', () => 0)
    vi.stubGlobal('cancelAnimationFrame', () => {})
    URL.createObjectURL = () => 'blob:x'
    URL.revokeObjectURL = () => {}

    const on = { onState: vi.fn(), onHearing: vi.fn(), onHeard: vi.fn(), onReply: vi.fn(), onDone: vi.fn(), onInterrupted: vi.fn(), onLevel: vi.fn(), onClosed: vi.fn() }
    const opening = openTalkLine('ws://x/api/jarvis/talk', on)
    await vi.waitFor(() => expect(socket).not.toBeNull())
    socket!.onopen!()
    const line = await opening
    const say = (event: object) => socket!.onmessage!({ data: JSON.stringify(event) })
    say({ type: 'partial', text: 'turn the' })
    say({ type: 'partial', text: 'turn the big light' })
    say({ type: 'transcript', text: 'Turn the big light off.' })
    say({ type: 'reply', text: 'Done.' })
    expect(on.onHearing.mock.calls).toEqual([['turn the'], ['turn the big light']])
    expect(on.onHeard).toHaveBeenCalledWith('Turn the big light off.')
    expect(on.onReply).toHaveBeenCalledWith('Done.')
    line.close()
    vi.unstubAllGlobals()
  })
})
