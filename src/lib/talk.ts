// Hands-free Talk: a voice line to Jarvis's own voice pipeline on the PC
// (Whisper hears you, Jarvis answers, his voice speaks), carried over the
// WebSocket at /api/jarvis/talk (server/talk.mjs).
//
// The page sends the microphone as 16 kHz 16-bit mono audio in 20 ms
// frames, and keeps sending while Jarvis speaks so you can talk over him
// (he stops). Jarvis sends JSON events (state, partial, transcript, reply,
// done, stop, approval, approval_done, working, working_done, model) and his voice as 16-bit audio at the rate his hello names, one
// message per sentence. When his voice has finished playing the page says
// {"type":"idle"} so he knows the speaker is quiet again.
//
// Dozing (Dylan, 2026-11-14): a Jarvis whose hello says wake_word: true
// can doze instead of hanging up. Pause sends {"type":"doze"}, and Jarvis
// also dozes by himself when Dylan's done ("anything else?" "no"). While
// dozing, Jarvis only listens for "Hey Jarvis" on the PC (nothing goes to
// Whisper or his brain), then says state listening again. Talk sends
// {"type":"wake"}. Muted, only silence goes out, so the wake word can't fire.
//
// Mute also means "I'm finished talking" (Dylan, 2026-11-17): tapping Mute
// sends {"type":"end_turn"}, so Jarvis answers what he has heard right
// away instead of waiting to be sure you've stopped.

import { readTalkDirect, writeTalkDirect } from './prefs'
import type { Approval, ApprovalBy } from '../types'

export type TalkState = 'listening' | 'thinking' | 'speaking' | 'dozing'

export interface TalkHandlers {
  /** Jarvis's side of the line changed state. */
  onState: (state: TalkState) => void
  /** What he has heard so far while you're still talking (replaced by each newer guess). joined: it carries on the question he was already answering. stable: how many leading words won't change again (null from an older Jarvis). */
  onHearing: (text: string, joined: boolean, stable: number | null) => void
  /** What he heard you say (one whole turn). joined: the earlier words plus what you added after he thought you were done. same: it says what the live words already said, so the bubble can stay as it is. */
  onHeard: (text: string, joined: boolean, same: boolean) => void
  /** More of Jarvis's reply text. */
  onReply: (added: string) => void
  /** Jarvis started something slow (label says what, e.g. "Searching the web."), or finished it (null). */
  onWorking: (label: string | null) => void
  /** Who is answering this reply: "claude", or "ornith" when he has fallen back to the local model. */
  onModel: (model: string) => void
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
  /** An approval was settled: by the page (a tap or a spoken yes/no) or the clock. */
  /** later: he said "wait", so the request is held rather than denied. */
  onApprovalDone: (id: string, ok: boolean, by: ApprovalBy, later: boolean) => void
}

/** One JSON event from Jarvis's side of the line (fields depend on its type). */
interface TalkEvent {
  type?: string
  state?: string
  text?: string
  rate?: number
  id?: string
  label?: string
  tool?: string
  summary?: string
  expires?: string
  joined?: boolean
  /** On a partial: how many leading words are settled. */
  stable?: number
  /** On a transcript: the final matches the live words but for punctuation and capitals. */
  same?: boolean
  model?: string
  ok?: boolean
  by?: string
  later?: boolean
  wake_word?: boolean
}

/** Who settled an approval, as one of the three the page knows. */
function approvalBy(by: string | undefined): ApprovalBy {
  if (by === 'page' || by === 'voice') return by
  return 'timeout'
}

export interface TalkLine {
  /** Hangs up: the microphone, the voice and the socket all stop. */
  close: () => void
  /**
   * Mutes or unmutes the microphone. Muted, the line stays open and Jarvis
   * keeps answering and speaking, but he hears only silence: the mic track
   * is switched off, so nothing it picks up leaves the phone. Muting also
   * tells him you've finished talking, so he answers at once.
   */
  setMuted: (muted: boolean) => void
  /** Whether this Jarvis can doze and wake on "Hey Jarvis" (older ones can only hang up). */
  canDoze: () => boolean
  /** Pause without hanging up: his voice stops and he listens only for "Hey Jarvis". */
  doze: () => void
  /** Talk again after dozing, same as saying "Hey Jarvis". */
  wake: () => void
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
/**
 * The cushion when his voice ran dry partway through a reply (a phone on a
 * slow network): a longer one, so the rest of the reply plays smoothly
 * instead of stopping and starting (Dylan, 2026-11-15: "it sometimes lags").
 */
const RECOVERY_CUSHION_S = 0.4
/** Each sentence fades in and out over this long, so its edges don't click (seconds). */
const EDGE_FADE_S = 0.004

/** A partial's settled word count as a whole number of zero or more, or null when Jarvis sent none. */
export function stableCount(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) return null
  return value
}

/**
 * True when Jarvis just decided you're done talking: he goes from listening
 * to thinking. That's when the "got it" sound plays (Dylan, 2026-11-16:
 * "so I know when Jarvis is done listening to me and is starting to respond").
 * Since 2026-11-16 he says thinking only once the turn is final (after the
 * short grace in which more words would be joined on), so the sound never
 * comes before you're done (Dylan: "it made me feel rushed").
 */
export function heardYouOut(before: TalkState, after: TalkState): boolean {
  return before === 'listening' && after === 'thinking'
}

/** The "got it" sound's two notes (Hz), how long each lasts, and how loud (0..1). */
const GOT_IT_NOTES = [660, 990]
const GOT_IT_NOTE_S = 0.07
const GOT_IT_VOLUME = 0.07

/**
 * Plays a very short, quiet two-note rise through the same path as his
 * voice, so it shares the speaker route and the echo cancelling. Each note
 * swells and fades, with no hard edges to click.
 */
function playGotIt(ctx: AudioContext, out: AudioNode) {
  const start = ctx.currentTime + 0.01
  GOT_IT_NOTES.forEach((hz, i) => {
    const at = start + i * GOT_IT_NOTE_S
    const tone = ctx.createOscillator()
    tone.type = 'sine'
    tone.frequency.value = hz
    const level = ctx.createGain()
    level.gain.setValueAtTime(0, at)
    level.gain.linearRampToValueAtTime(GOT_IT_VOLUME, at + 0.012)
    level.gain.exponentialRampToValueAtTime(0.0001, at + GOT_IT_NOTE_S + 0.05)
    tone.connect(level).connect(out)
    tone.start(at)
    tone.stop(at + GOT_IT_NOTE_S + 0.06)
  })
}

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
 * The microphone rates the context follows: full-quality ones only. PR #80
 * matched 44.1 and 48 kHz and fixed the iPhone speaker's crackle; following
 * the 16 or 24 kHz call-quality rates too (PR #83) brought it back (Dylan,
 * 2026-11-15 8:43 PM), so those use the browser's default again.
 */
const MIN_CONTEXT_RATE = 44100
const MAX_CONTEXT_RATE = 96000

/**
 * The rate the audio context should run at: the microphone's own when it's
 * a full-quality one. iPhones crackle when the context and the open
 * microphone run at different rates (44.1 vs 48 kHz).
 * Null means use the browser's default.
 */
export function contextRate(micRate: unknown): number | null {
  if (typeof micRate !== 'number' || !Number.isFinite(micRate)) return null
  if (micRate < MIN_CONTEXT_RATE || micRate > MAX_CONTEXT_RATE) return null
  return micRate
}

/** Why Talk hung up by itself after the phone's audio changed under it. */
/** What the page says when the microphone stopped and couldn't be reopened. */
export const MIC_LOST_MESSAGE = 'Jarvis stopped hearing you. Tap Talk to start again.'

/** What the page says after a goodbye ended the call for good. */
export const BYE_MESSAGE = 'Goodbye. Tap Talk when you want him again.'
const INTERRUPTED_MESSAGE = 'Your phone’s audio was interrupted, so Talk stopped. Tap Talk to start again.'

/**
 * True when iOS has taken the audio away (a call, another app's sound, the
 * screen locking). A context that comes back from that often runs at the
 * wrong rate and crackles the whole time (Dylan, 2026-11-15, a Talk line
 * left dozing for an hour), so the line is rebuilt rather than resumed.
 */
export function audioWasInterrupted(state: string): boolean {
  return state === 'interrupted' || state === 'suspended'
}

/** The rate the microphone says it runs at, or null when it doesn't say. */
function micRateOf(stream: MediaStream): number | null {
  const rate = stream.getAudioTracks()[0]?.getSettings?.().sampleRate
  if (typeof rate !== 'number') return null
  return rate
}

/** True when the microphone now runs at a different full-quality rate than the audio context it was opened with. */
function rateDrifted(stream: MediaStream, ctx: AudioContext): boolean {
  const rate = contextRate(micRateOf(stream))
  if (rate === null || rate === ctx.sampleRate) return false
  console.info(`[talk] microphone moved to ${rate} Hz, audio is ${ctx.sampleRate} Hz: starting fresh`)
  return true
}

/** The audio context, running at the microphone's own rate (see contextRate). */
function makeContext(stream: MediaStream): AudioContext {
  const micRate = stream.getAudioTracks()[0]?.getSettings?.().sampleRate
  const rate = contextRate(micRate)
  let ctx: AudioContext | null = null
  if (rate !== null) {
    try { ctx = new AudioContext({ sampleRate: rate }) } catch { /* rate not allowed here; use the default */ }
  }
  if (ctx === null) ctx = new AudioContext()
  // Kept so a crackle report can be matched to the rates in Web Inspector.
  console.info(`[talk] microphone ${String(micRate)} Hz, audio ${ctx.sampleRate} Hz`)
  return ctx
}

/** /talk?direct=1 or ?direct=0 saves how this browser plays his voice (see readTalkDirect). */
function rememberOutputChoice() {
  if (typeof location === 'undefined') return
  const direct = new URLSearchParams(location.search).get('direct')
  if (direct === '1') writeTalkDirect(true)
  if (direct === '0') writeTalkDirect(false)
}

/**
 * Whether Talk can start with no tap: the microphone is already allowed for
 * this page and the browser lets sound play. iOS Safari says no until the
 * first tap; a desktop browser that was allowed before usually says yes.
 */
export async function canTalkUnprompted(): Promise<boolean> {
  try {
    // 'microphone' isn't in every browser's PermissionName list yet, hence the cast.
    const mic = await navigator.permissions?.query({ name: 'microphone' as PermissionName })
    if (mic?.state !== 'granted') return false
  } catch {
    return false
  }
  if (typeof AudioContext === 'undefined') return false
  // A context made without a tap starts suspended where sound is blocked.
  const probe = new AudioContext()
  const running = probe.state === 'running'
  void probe.close().catch(() => {})
  return running
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

  const ctx = makeContext(stream)
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
  let mic = ctx.createMediaStreamSource(stream)
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
  rememberOutputChoice()
  let speaker: HTMLAudioElement | null = null
  if (readTalkDirect()) voice.connect(ctx.destination)
  else speaker = routeToSpeaker(ctx, voice)

  const ws = new WebSocket(url)
  ws.binaryType = 'arraybuffer'

  let rate = 22050
  let dozes = false
  // True while the microphone is being reopened, so two no_audio events don't race.
  let restarting = false
  let state: TalkState = 'listening'
  let playing: AudioBufferSourceNode[] = []
  let playAt = 0
  // True once a sentence of this reply has been scheduled, so running dry later uses the longer cushion.
  let midReply = false
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
    midReply = false
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
    if (playAt < ctx.currentTime + 0.02) {
      let cushion = PLAYBACK_CUSHION_S
      if (midReply) cushion = RECOVERY_CUSHION_S
      playAt = ctx.currentTime + cushion
    }
    // His first sentence of a reply: if the phone's audio rate moved under us, start fresh.
    if (!midReply && rateDrifted(stream, ctx)) {
      shutDown(INTERRUPTED_MESSAGE)
      return
    }
    midReply = true
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
    midReply = false
    playAt = 0
    for (const s of queued) {
      s.onended = null
      try { s.stop() } catch { /* already finished */ }
    }
  }

  /** Acts on one JSON event from Jarvis. */
  function handleEvent(event: TalkEvent) {
    if (event.type === 'hello') {
      if (typeof event.rate === 'number') rate = event.rate
      dozes = event.wake_word === true
    } else if (event.type === 'state' && isTalkState(event.state)) {
      // He stopped listening and started on an answer: a soft "got it" so you know you can stop.
      if (heardYouOut(state, event.state)) playGotIt(ctx, voice)
      // Dozing by himself ("that's all"): anything still queued of his sign-off plays out.
      state = event.state
      on.onState(event.state)
    } else if (event.type === 'partial' && event.text) on.onHearing(event.text, event.joined === true, stableCount(event.stable))
    else if (event.type === 'transcript' && event.text) on.onHeard(event.text, event.joined === true, event.same === true)
    else if (event.type === 'reply' && event.text) on.onReply(event.text)
    else if (event.type === 'working') on.onWorking(event.label ?? '')
    else if (event.type === 'working_done') on.onWorking(null)
    else if (event.type === 'model' && typeof event.model === 'string') on.onModel(event.model)
    else if (event.type === 'done') {
      replyDone = true
      on.onDone()
      maybeIdle()
    } else if (event.type === 'stop') {
      silence()
      on.onInterrupted()
    } else if (event.type === 'bye') {
      // "Goodbye", "talk to you later" (Dylan, 2026-11-17): the call is over,
      // not paused. His sign-off has already played (he sends this after our
      // idle), so hang up: mic off, no "Hey Jarvis", and a plain note instead
      // of "the line dropped". Only Talk starts it again.
      shutDown(BYE_MESSAGE)
    } else if (event.type === 'no_audio') {
      void restartMic()
    } else if (event.type === 'approval' && typeof event.id === 'string' && typeof event.summary === 'string') {
      on.onApproval({ id: event.id, tool: event.tool ?? '', summary: event.summary, expires: event.expires ?? '' })
    } else if (event.type === 'approval_done' && typeof event.id === 'string') {
      on.onApprovalDone(event.id, event.ok === true, approvalBy(event.by), event.later === true)
    }
  }

  /**
   * Jarvis says the line is open but he's had no sound from us for a while
   * (`no_audio`; Dylan, 2026-11-18: "that will be all" never reached him
   * because the mic had quietly stopped). Wakes the audio context and opens
   * the microphone afresh; if that can't be done, hangs up with a plain
   * note so it's clear he can't hear, instead of a line that looks alive.
   */
  async function restartMic() {
    if (closed || restarting) return
    restarting = true
    try {
      if (ctx.state === 'suspended') await ctx.resume().catch(() => {})
      const fresh = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } })
      if (closed) {
        for (const t of fresh.getTracks()) t.stop()
        return
      }
      mic.disconnect()
      for (const t of stream.getTracks()) t.stop()
      stream = fresh
      for (const t of stream.getAudioTracks()) t.enabled = !muted
      mic = ctx.createMediaStreamSource(stream)
      mic.connect(micLevel)
      mic.connect(capture)
    } catch {
      shutDown(MIC_LOST_MESSAGE)
    } finally {
      restarting = false
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
  // Muted, a frame of silence goes instead, so his listening clock keeps
  // running and a half-finished turn still ends.
  let muted = false
  capture.port.onmessage = (e: MessageEvent<ArrayBuffer>) => {
    if (ws.readyState !== WebSocket.OPEN) return
    if (muted) ws.send(new ArrayBuffer(e.data.byteLength))
    else ws.send(e.data)
  }

  /**
   * Switches the mic track itself off too, so muting doesn't rely on the
   * frames alone. Going muted also says the turn is over, so Jarvis answers
   * what he has heard without waiting out the quiet.
   */
  function setMuted(next: boolean) {
    const justMuted = next && !muted
    muted = next
    for (const t of stream.getAudioTracks()) t.enabled = !next
    if (justMuted) tell('end_turn')
  }
  ws.onmessage = (e: MessageEvent<ArrayBuffer | string>) => {
    if (typeof e.data === 'string') {
      try { handleEvent(JSON.parse(e.data)) } catch { /* not JSON: ignore it */ }
    } else play(e.data)
  }
  ws.onerror = null
  ws.onclose = () => shutDown('The line to Jarvis dropped')
  // For Jarvis's log, so a crackle report can be matched to the phone's audio rates.
  ws.send(JSON.stringify({ type: 'client', mic_rate: micRateOf(stream), audio_rate: ctx.sampleRate, agent: navigator.userAgent }))
  ctx.onstatechange = () => {
    if (audioWasInterrupted(ctx.state)) shutDown(INTERRUPTED_MESSAGE)
  }
  frame = requestAnimationFrame(tick)
  on.onState('listening')

  /** Tells Jarvis one thing about the line, if it's still open. */
  function tell(type: string) {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type }))
  }

  /** Pause, keeping the line: his voice stops now and he listens only for "Hey Jarvis". */
  function doze() {
    silence()
    tell('doze')
    state = 'dozing'
    on.onState('dozing')
  }

  /** Talk after dozing: he's listening again right away (he confirms with a state event too). */
  function wake() {
    tell('wake')
    state = 'listening'
    on.onState('listening')
  }

  return { close: () => shutDown(null), setMuted, canDoze: () => dozes, doze, wake }
}

/** Whether a state Jarvis sent is one the line knows. */
function isTalkState(value: unknown): value is TalkState {
  return value === 'listening' || value === 'thinking' || value === 'speaking' || value === 'dozing'
}
