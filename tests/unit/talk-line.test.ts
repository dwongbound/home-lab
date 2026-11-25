// src/lib/talk.ts: the voice line's address, its audio conversions, and
// that it refuses plainly when there's no microphone, and which of
// Jarvis's events reach which handler.
import { describe, expect, it, vi } from 'vitest'
import { BYE_MESSAGE, canTalkUnprompted, makeResampler, openTalkLine, pcm16ToFloat, remainingAfter, softenEdges, talkUrl } from '../../src/lib/talk'

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

  it("fades the first and last few milliseconds of a sentence so its edges don't pop", () => {
    const floats = new Float32Array(2400).fill(1)
    softenEdges(floats, 24000)
    expect(floats[0]).toBe(0)
    expect(floats[floats.length - 1]).toBe(0)
    expect(floats[48]).toBeCloseTo(0.5, 1)
    // The middle is untouched.
    expect(floats[1200]).toBe(1)
  })

  it('refuses in words when the browser has no microphone', async () => {
    const on = { onState: vi.fn(), onHearing: vi.fn(), onHeard: vi.fn(), onReply: vi.fn(), onDone: vi.fn(), onInterrupted: vi.fn(), onLevel: vi.fn(), onClosed: vi.fn(), onApproval: vi.fn(), onApprovalDone: vi.fn(), onWorking: vi.fn(), onModel: vi.fn() }
    await expect(openTalkLine('ws://x/api/jarvis/talk', on)).rejects.toThrow('This browser can’t send your voice to Jarvis')
  })

  it('hands your words over while you talk, then the whole turn, then his reply, and his approval requests', async () => {
    // Just enough of a browser's audio and WebSocket for the line to open.
    const node = () => ({ connect: (next: unknown) => next, disconnect: () => {}, gain: { value: 1 }, fftSize: 0, getFloatTimeDomainData: () => {} })
    class FakeContext {
      state = 'running'
      destination = node()
      currentTime = 0
      audioWorklet = { addModule: async () => {} }
      createMediaStreamSource = node
      createAnalyser = node
      createGain = node
      createMediaStreamDestination = () => ({ stream: 'his voice' })
      close = async () => {}
    }
    // His voice plays through an <audio> element, so the browser's echo cancellation hears it.
    const players: { srcObject: unknown; paused: boolean }[] = []
    class FakeAudio {
      srcObject: unknown = null
      autoplay = false
      paused = true
      constructor() { players.push(this) }
      play = async () => { this.paused = false }
      pause = () => { this.paused = true }
    }
    vi.stubGlobal('Audio', FakeAudio)
    let worklet: { port: { onmessage: ((e: { data: ArrayBuffer }) => void) | null } } | null = null
    class FakeWorklet { port: { onmessage: unknown } = { onmessage: null }; connect = (next: unknown) => next; constructor() { worklet = this as never } }
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
    const track = { enabled: true, stop: vi.fn() }
    // The first microphone, then a fresh one each time the line reopens it.
    const fresh = { enabled: true, stop: vi.fn() }
    const getUserMedia = vi.fn(async () => {
      const t = getUserMedia.mock.calls.length === 1 ? track : fresh
      return { getTracks: () => [t], getAudioTracks: () => [t] }
    })
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } })
    vi.stubGlobal('requestAnimationFrame', () => 0)
    vi.stubGlobal('cancelAnimationFrame', () => {})
    URL.createObjectURL = () => 'blob:x'
    URL.revokeObjectURL = () => {}

    const on = { onState: vi.fn(), onHearing: vi.fn(), onHeard: vi.fn(), onReply: vi.fn(), onDone: vi.fn(), onInterrupted: vi.fn(), onLevel: vi.fn(), onClosed: vi.fn(), onApproval: vi.fn(), onApprovalDone: vi.fn(), onWorking: vi.fn(), onModel: vi.fn() }
    const opening = openTalkLine('ws://x/api/jarvis/talk', on)
    await vi.waitFor(() => expect(socket).not.toBeNull())
    socket!.onopen!()
    const line = await opening
    const say = (event: object) => socket!.onmessage!({ data: JSON.stringify(event) })
    say({ type: 'partial', text: 'turn the' })
    say({ type: 'partial', text: 'turn the big light', stable: 2 })
    say({ type: 'transcript', text: 'Turn the big light off.' })
    // Who's answering: the chip over the reply follows this.
    say({ type: 'model', model: 'ornith' })
    say({ type: 'reply', text: 'Done.' })
    expect(on.onModel).toHaveBeenCalledWith('ornith')
    expect(on.onHearing.mock.calls).toEqual([['turn the', false, null], ['turn the big light', false, 2]])
    expect(on.onHeard).toHaveBeenCalledWith('Turn the big light off.', false, false)
    // Carrying on after he thought you were done: the words come back joined onto the same question.
    say({ type: 'partial', text: 'Turn the big light off. And the', joined: true })
    say({ type: 'transcript', text: 'Turn the big light off. And the fan.', joined: true, same: true })
    expect(on.onHearing).toHaveBeenLastCalledWith('Turn the big light off. And the', true, null)
    expect(on.onHeard).toHaveBeenLastCalledWith('Turn the big light off. And the fan.', true, true)
    expect(on.onReply).toHaveBeenCalledWith('Done.')
    // A slow lookup: the orb's working sweep starts with what he's doing, then stops.
    say({ type: 'working', label: 'Checking traffic to Disneyland.' })
    say({ type: 'working_done' })
    expect(on.onWorking.mock.calls).toEqual([['Checking traffic to Disneyland.'], [null]])
    // Asking before he runs something, then hearing it was answered.
    say({ type: 'approval', id: 'a7', tool: 'run_command', summary: 'ls ~/jarvis', expires: '2026-11-11T12:20:00Z' })
    say({ type: 'approval_done', id: 'a7', ok: true, by: 'voice' })
    expect(on.onApproval).toHaveBeenCalledWith({ id: 'a7', tool: 'run_command', summary: 'ls ~/jarvis', expires: '2026-11-11T12:20:00Z' })
    expect(on.onApprovalDone).toHaveBeenCalledWith('a7', true, 'voice', false)
    // "Wait": held for later, not denied.
    say({ type: 'approval_done', id: 'a8', ok: false, by: 'voice', later: true })
    expect(on.onApprovalDone).toHaveBeenLastCalledWith('a8', false, 'voice', true)
    expect(players).toHaveLength(1)
    expect(players[0].srcObject).toBe('his voice')
    // Mute: the line stays open and his replies still arrive, but only silence goes out and the mic track is off.
    const sent = (socket as unknown as { send: ReturnType<typeof vi.fn> }).send
    const frame = new Int16Array([1200, -800]).buffer
    worklet!.port.onmessage!({ data: frame })
    expect(sent).toHaveBeenLastCalledWith(frame)
    line.setMuted(true)
    expect(track.enabled).toBe(false)
    // Muting also says "I'm finished talking", once.
    expect(sent).toHaveBeenLastCalledWith(JSON.stringify({ type: 'end_turn' }))
    line.setMuted(true)
    expect(sent.mock.calls.filter((c) => c[0] === JSON.stringify({ type: 'end_turn' }))).toHaveLength(1)
    worklet!.port.onmessage!({ data: frame })
    const quiet = sent.mock.lastCall![0] as ArrayBuffer
    expect(quiet.byteLength).toBe(frame.byteLength)
    expect([...new Int16Array(quiet)]).toEqual([0, 0])
    say({ type: 'reply', text: 'Still here.' })
    expect(on.onReply).toHaveBeenLastCalledWith('Still here.')
    line.setMuted(false)
    expect(track.enabled).toBe(true)
    worklet!.port.onmessage!({ data: frame })
    expect(sent).toHaveBeenLastCalledWith(frame)
    // Dozing: a Jarvis that says wake_word can pause without hanging up.
    expect(line.canDoze()).toBe(false)
    say({ type: 'hello', rate: 24000, wake_word: true })
    expect(line.canDoze()).toBe(true)
    line.doze()
    expect(sent).toHaveBeenLastCalledWith(JSON.stringify({ type: 'doze' }))
    expect(on.onState).toHaveBeenLastCalledWith('dozing')
    line.wake()
    expect(sent).toHaveBeenLastCalledWith(JSON.stringify({ type: 'wake' }))
    expect(on.onState).toHaveBeenLastCalledWith('listening')
    // He dozes by himself when you're done, and "Hey Jarvis" brings him back.
    say({ type: 'state', state: 'dozing' })
    expect(on.onState).toHaveBeenLastCalledWith('dozing')
    say({ type: 'woke', by: 'voice' })
    say({ type: 'state', state: 'listening' })
    expect(on.onState).toHaveBeenLastCalledWith('listening')
    // The line is open but he's had no sound from us: the microphone is opened afresh, the old one let go.
    say({ type: 'no_audio', seconds: 20 })
    await vi.waitFor(() => expect(getUserMedia).toHaveBeenCalledTimes(2))
    await vi.waitFor(() => expect(track.stop).toHaveBeenCalled())
    expect(fresh.stop).not.toHaveBeenCalled()
    expect(on.onClosed).not.toHaveBeenCalled()
    // "Goodbye": the call ends for good. Mic off, speaker stopped, and a
    // plain note rather than "the line dropped", even when the socket closes after.
    say({ type: 'bye' })
    expect(track.stop).toHaveBeenCalled()
    expect(players[0].paused).toBe(true)
    expect(on.onClosed).toHaveBeenCalledTimes(1)
    expect(on.onClosed).toHaveBeenCalledWith(BYE_MESSAGE)
    const closing = socket as unknown as { onclose?: () => void }
    closing.onclose?.()
    expect(on.onClosed).toHaveBeenCalledTimes(1)
    line.close()
    vi.unstubAllGlobals()
  })
})

describe('starting Talk with no tap (/talk)', () => {
  /** Stubs the microphone permission and whether a fresh AudioContext may play. */
  function stub(mic: string | 'throws', audio: 'running' | 'suspended') {
    const query = mic === 'throws' ? async () => { throw new Error('unsupported') } : async () => ({ state: mic })
    vi.stubGlobal('navigator', { permissions: { query } })
    vi.stubGlobal('AudioContext', class { state = audio; close = async () => {} })
  }

  it('goes ahead when the microphone is allowed and sound can play', async () => {
    stub('granted', 'running')
    expect(await canTalkUnprompted()).toBe(true)
    vi.unstubAllGlobals()
  })

  it('waits for a tap when sound is blocked (iOS), the microphone was never allowed, or the browser can’t say', async () => {
    stub('granted', 'suspended')
    expect(await canTalkUnprompted()).toBe(false)
    stub('prompt', 'running')
    expect(await canTalkUnprompted()).toBe(false)
    stub('throws', 'running')
    expect(await canTalkUnprompted()).toBe(false)
    vi.unstubAllGlobals()
  })
})

describe('remainingAfter', () => {
  // Pausing mid-reply keeps only what hasn't been heard, from the exact spot.
  it('drops finished sentences, keeps the current one from where it paused and the rest whole', () => {
    const queued = [
      { buffer: 'a', startAt: 0, duration: 1 },
      { buffer: 'b', startAt: 1, duration: 2 },
      { buffer: 'c', startAt: 3, duration: 1 },
    ]
    expect(remainingAfter(queued, 1.5)).toEqual([
      { buffer: 'b', offset: 0.5 },
      { buffer: 'c', offset: 0 },
    ])
  })

  it('keeps nothing once everything has played', () => {
    expect(remainingAfter([{ buffer: 'a', startAt: 0, duration: 1 }], 1)).toEqual([])
  })
})
