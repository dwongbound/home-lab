// Hands-free Talk: a voice line to Jarvis's own voice pipeline on the PC
// (Whisper hears you, Jarvis answers, his voice speaks), carried over the
// WebSocket at /api/jarvis/talk (server/talk.mjs).
//
// The page sends the microphone as 16 kHz 16-bit mono audio in 20 ms
// frames, and keeps sending while Jarvis speaks so you can talk over him
// (he stops). Jarvis sends JSON events (state, partial, transcript, reply,
// done, stop, approval, approval_done) and his voice as 16-bit audio at the rate his hello names, one
// message per sentence. When his voice has finished playing the page says
// {"type":"idle"} so he knows the speaker is quiet again.

import type { Approval, ApprovalBy } from '../types'

export type TalkState = 'listening' | 'thinking' | 'speaking'

export interface TalkHandlers {
  /** Jarvis's side of the line changed state. */
  onState: (state: TalkState) => void
  /** What Whisper has heard so far while you're still talking (replaced by each newer guess). */
  onHearing: (text: string) => void
  /** What Whisper heard you say (one whole turn). */
  onHeard: (text: string) => void
  /** More of Jarvis's reply text. */
  onReply: (added: string) => void
  /** Jarvis finished this reply. */
  onDone: () => void
  /** You talked over him, so the rest of the reply was dropped. */
  onInterrupted: () => void
  /** About 60 times a second: how loud the voice that matters now is (yours while listening, his while speaking), 0..1. */
  onLevel: (level: number) => void
  /** The line dropped. message says why, in words for the page. */
  onClosed: (message: string) => void
  /** Jarvis wants an OK to write a file or run a command (answer by tap, or say yes or no). */
  onApproval: (approval: Approval) => void
  /** An approval was settled: by the page (a tap or a spoken yes/no), Telegram, or the clock. */
  onApprovalDone: (id: string, ok: boolean, by: ApprovalBy) => void
}

/** One JSON event from Jarvis's side of the line (fields depend on its type). */
interface TalkEvent {
  type?: string
  state?: string
  text?: string
  rate?: number
  id?: string
  tool?: string
  summary?: string
  expires?: string
  ok?: boolean
  by?: string
}

/** Who settled an approval, as one of the four the page knows. */
function approvalBy(by: string | undefined): ApprovalBy {
  if (by === 'page' || by === 'voice' || by === 'telegram') return by
  return 'timeout'
}

export interface TalkLine {
  /** Hangs up: the microphone, the voice and the socket all stop. */
  close: () => void
}

/** The voice line's address on this page's own host (wss on https). */
export function talkUrl(loc: { protocol: string; host: string }): string {
  const scheme = loc.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${scheme}//${loc.host}/api/jarvis/talk`
}

/** Turns 16-bit little-endian samples into the -1..1 floats Web Audio plays. */
export function pcm16ToFloat(bytes: ArrayBuffer): Float32Array<ArrayBuffer> {
  const view = new DataView(bytes)
  const out = new Float32Array(Math.floor(bytes.byteLength / 2))
  for (let i = 0; i < out.length; i++) out[i] = view.getInt16(i * 2, true) / 0x8000
  return out
}

/**
 * Makes a resampler from the microphone's rate down to 16 kHz that cuts the
 * result into 20 ms frames (320 samples, 640 bytes). Feed it the
 * microphone's chunks in order; it returns the whole frames finished so far.
 * It runs inside the audio worklet, so it must not use anything outside
 * itself (its source is copied there as text).
 */
export function makeResampler(fromRate: number): (chunk: Float32Array) => Int16Array[] {
  const step = fromRate / 16000
  // Position of the next output sample, counted in input samples from the
  // start of the current chunk. Between -1 and 0 it falls between the last
  // chunk's final sample (carry) and this chunk's first.
  let at = 0
  let carry = 0
  let frame = new Int16Array(320)
  let filled = 0
  return function resample(chunk) {
    const done: Int16Array[] = []
    while (at < chunk.length - 1) {
      let a
      let b
      let f
      if (at < 0) {
        a = carry
        b = chunk[0]
        f = at + 1
      } else {
        const i = Math.floor(at)
        a = chunk[i]
        b = chunk[i + 1]
        f = at - i
      }
      const s = Math.max(-1, Math.min(1, a + (b - a) * f))
      frame[filled++] = Math.round(s * 0x7fff)
      if (filled === frame.length) {
        done.push(frame)
        frame = new Int16Array(320)
        filled = 0
      }
      at += step
    }
    carry = chunk[chunk.length - 1]
    at -= chunk.length
    return done
  }
}

// The audio worklet: runs on the audio thread, resamples the microphone and
// posts each 20 ms frame's bytes back to the page.
const CAPTURE_WORKLET = `
const makeResampler = (${makeResampler.toString()});
class TalkCapture extends AudioWorkletProcessor {
  constructor() { super(); this.resample = makeResampler(sampleRate) }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0]
    if (ch && ch.length > 0) for (const f of this.resample(ch)) this.port.postMessage(f.buffer, [f.buffer])
    return true
  }
}
registerProcessor('talk-capture', TalkCapture)
`

/** Root-mean-square loudness of what an analyser hears, scaled so speech lands around 0.5-1. */
function loudness(analyser: AnalyserNode, samples: Float32Array<ArrayBuffer>): number {
  analyser.getFloatTimeDomainData(samples)
  let sum = 0
  for (const s of samples) sum += s * s
  return Math.min(1, Math.sqrt(sum / samples.length) * 9)
}

/** How far ahead his first sentence is scheduled, so later ones arrive in time (seconds). */
const PLAYBACK_CUSHION_S = 0.15
/** Each sentence fades in and out over this long, so its edges don't click (seconds). */
const EDGE_FADE_S = 0.004

/**
 * Fades the first and last few milliseconds of a sentence in place. Each
 * sentence is made on its own, so it can start or stop mid-wave; a hard
 * edge there is the "pop" you hear between sentences.
 */
export function softenEdges(floats: Float32Array, rate: number): void {
  const n = Math.min(Math.floor(rate * EDGE_FADE_S), Math.floor(floats.length / 2))
  for (let i = 0; i < n; i++) {
    const gain = i / n
    floats[i] *= gain
    floats[floats.length - 1 - i] *= gain
  }
}

/**
 * Sends his voice to the speaker through an <audio> element rather than
 * straight out of the audio graph. Browsers' echo cancellation listens to
 * what media elements play, but not always to Web Audio output, so this is
 * what stops the microphone hearing him as you. Falls back to the plain
 * graph where a browser can't do it. Returns the element to pause on hang-up.
 */
function routeToSpeaker(ctx: AudioContext, voice: AudioNode): HTMLAudioElement | null {
  if (typeof ctx.createMediaStreamDestination !== 'function' || typeof Audio !== 'function') {
    voice.connect(ctx.destination)
    return null
  }
  const out = ctx.createMediaStreamDestination()
  voice.connect(out)
  const element = new Audio()
  element.srcObject = out.stream
  element.autoplay = true
  // Talk was a tap, so this is allowed; if not, fall back to the graph.
  Promise.resolve(element.play()).catch(() => {
    voice.disconnect(out)
    voice.connect(ctx.destination)
  })
  return element
}

/**
 * Opens the microphone and the line to Jarvis. Resolves once both are up,
 * or throws an Error whose message can be shown as is (no microphone, or
 * Jarvis didn't pick up).
 */
export async function openTalkLine(url: string, on: TalkHandlers): Promise<TalkLine> {
  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia || typeof AudioWorkletNode === 'undefined') {
    throw new Error('This browser can’t send your voice to Jarvis')
  }
  let stream: MediaStream
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } })
  } catch {
    throw new Error('Jarvis can’t hear you: allow the microphone for this page')
  }

  const ctx = new AudioContext()
  // Safari starts a context suspended until a tap; Talk was a tap.
  if (ctx.state === 'suspended') await ctx.resume().catch(() => {})
  const moduleUrl = URL.createObjectURL(new Blob([CAPTURE_WORKLET], { type: 'text/javascript' }))
  try {
    await ctx.audioWorklet.addModule(moduleUrl)
  } finally {
    URL.revokeObjectURL(moduleUrl)
  }

  // Microphone: into the analyser (for the orb) and the worklet (for Jarvis).
  // The worklet feeds a silent gain so the browser keeps running it.
  const mic = ctx.createMediaStreamSource(stream)
  const micLevel = ctx.createAnalyser()
  micLevel.fftSize = 512
  mic.connect(micLevel)
  const capture = new AudioWorkletNode(ctx, 'talk-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1] })
  const silent = ctx.createGain()
  silent.gain.value = 0
  mic.connect(capture).connect(silent).connect(ctx.destination)

  // Jarvis's voice: every sentence goes through one analyser to the speaker.
  const voice = ctx.createGain()
  const voiceLevel = ctx.createAnalyser()
  voiceLevel.fftSize = 512
  voice.connect(voiceLevel)
  const speaker = routeToSpeaker(ctx, voice)

  const ws = new WebSocket(url)
  ws.binaryType = 'arraybuffer'

  let rate = 22050
  let state: TalkState = 'listening'
  let playing: AudioBufferSourceNode[] = []
  let playAt = 0
  let replyDone = false
  let closed = false
  let frame = 0
  const samples = new Float32Array(512)

  /** The orb follows you while Jarvis listens and him while he speaks, never his voice from your speaker. */
  function tick() {
    if (state === 'listening') on.onLevel(loudness(micLevel, samples))
    else if (playing.length > 0) on.onLevel(loudness(voiceLevel, samples))
    frame = requestAnimationFrame(tick)
  }

  /** Tells Jarvis the speaker is quiet, once his whole reply has played. */
  function maybeIdle() {
    if (!replyDone || playing.length > 0) return
    replyDone = false
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'idle' }))
  }

  /** Queues one sentence of his voice right after the one before it. */
  function play(bytes: ArrayBuffer) {
    const floats = pcm16ToFloat(bytes)
    if (floats.length === 0) return
    softenEdges(floats, rate)
    const buffer = ctx.createBuffer(1, floats.length, rate)
    buffer.copyToChannel(floats, 0)
    const source = ctx.createBufferSource()
    source.buffer = buffer
    source.connect(voice)
    // A short cushion before the first sentence (or after running dry) so the
    // next one is usually here before this one ends: no gaps, no pops.
    if (playAt < ctx.currentTime + 0.02) playAt = ctx.currentTime + PLAYBACK_CUSHION_S
    source.start(playAt)
    playAt += buffer.duration
    playing.push(source)
    source.onended = () => {
      playing = playing.filter((s) => s !== source)
      maybeIdle()
    }
  }

  /** Drops whatever of his voice is still queued (you talked over him). */
  function silence() {
    const queued = playing
    playing = []
    replyDone = false
    playAt = 0
    for (const s of queued) {
      s.onended = null
      try { s.stop() } catch { /* already finished */ }
    }
  }

  /** Acts on one JSON event from Jarvis. */
  function handleEvent(event: TalkEvent) {
    if (event.type === 'hello' && typeof event.rate === 'number') rate = event.rate
    else if (event.type === 'state' && (event.state === 'listening' || event.state === 'thinking' || event.state === 'speaking')) {
      state = event.state
      on.onState(event.state)
    } else if (event.type === 'partial' && event.text) on.onHearing(event.text)
    else if (event.type === 'transcript' && event.text) on.onHeard(event.text)
    else if (event.type === 'reply' && event.text) on.onReply(event.text)
    else if (event.type === 'done') {
      replyDone = true
      on.onDone()
      maybeIdle()
    } else if (event.type === 'stop') {
      silence()
      on.onInterrupted()
    } else if (event.type === 'approval' && typeof event.id === 'string' && typeof event.summary === 'string') {
      on.onApproval({ id: event.id, tool: event.tool ?? '', summary: event.summary, expires: event.expires ?? '' })
    } else if (event.type === 'approval_done' && typeof event.id === 'string') {
      on.onApprovalDone(event.id, event.ok === true, approvalBy(event.by))
    }
  }

  /** Stops everything; message goes to onClosed unless the page hung up itself. */
  function shutDown(message: string | null) {
    if (closed) return
    closed = true
    cancelAnimationFrame(frame)
    silence()
    capture.port.onmessage = null
    for (const t of stream.getTracks()) t.stop()
    speaker?.pause()
    void ctx.close().catch(() => {})
    if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) ws.close()
    if (message !== null) on.onClosed(message)
  }

  await new Promise<void>((resolve, reject) => {
    ws.onopen = () => resolve()
    ws.onerror = () => {
      shutDown(null)
      reject(new Error('Jarvis didn’t pick up. Is he running on the PC?'))
    }
  })

  // From here on, every 20 ms frame of the microphone goes to Jarvis.
  capture.port.onmessage = (e: MessageEvent<ArrayBuffer>) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(e.data)
  }
  ws.onmessage = (e: MessageEvent<ArrayBuffer | string>) => {
    if (typeof e.data === 'string') {
      try { handleEvent(JSON.parse(e.data)) } catch { /* not JSON: ignore it */ }
    } else play(e.data)
  }
  ws.onerror = null
  ws.onclose = () => shutDown('The line to Jarvis dropped')
  frame = requestAnimationFrame(tick)
  on.onState('listening')

  return { close: () => shutDown(null) }
}
