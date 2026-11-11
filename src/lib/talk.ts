// Hands-free talk, mockup edition. The microphone's loudness drives the orb
// while Jarvis listens, and the browser's own speech recognition (Chrome and
// Safari have it) turns one spoken turn into text. The real build swaps
// recognition for Jarvis's /talk pipeline on the PC (Whisper, then Jarvis,
// then his voice), but the loudness part stays the same.

/** The browser's speech recognition constructor, if it has one. */
function recognitionClass(): (new () => SpeechRecognitionLike) | null {
  const w = window as unknown as { SpeechRecognition?: new () => SpeechRecognitionLike; webkitSpeechRecognition?: new () => SpeechRecognitionLike }
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null
}

/** The few parts of SpeechRecognition used here (it isn't in TypeScript's DOM types everywhere). */
interface SpeechRecognitionLike {
  lang: string
  interimResults: boolean
  continuous: boolean
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null
  onend: (() => void) | null
  onerror: (() => void) | null
  start: () => void
  abort: () => void
}

/** True when this browser can turn speech into text by itself. */
export function canRecognize(): boolean {
  return typeof window !== 'undefined' && recognitionClass() !== null
}

/**
 * Listens for one spoken turn and resolves with what was said, or null if
 * nothing was heard (or it was stopped). onPartial shows the words as they
 * come. The returned stop() ends it early.
 */
export function listenOnce(onPartial: (text: string) => void): { result: Promise<string | null>; stop: () => void } {
  const Rec = recognitionClass()
  if (Rec === null) return { result: Promise.resolve(null), stop: () => {} }
  const rec = new Rec()
  rec.lang = 'en-US'
  rec.interimResults = true
  rec.continuous = false
  let heard = ''
  const result = new Promise<string | null>((resolve) => {
    rec.onresult = (e) => {
      let text = ''
      for (let i = 0; i < e.results.length; i++) text += e.results[i][0].transcript
      heard = text
      onPartial(text)
    }
    // Recognition ends by itself after a pause; that's the end of the turn.
    rec.onend = () => resolve(heard.trim() === '' ? null : heard.trim())
    rec.onerror = () => resolve(null)
  })
  rec.start()
  return { result, stop: () => rec.abort() }
}

/**
 * Opens the microphone and calls onLevel (0..1) about 60 times a second
 * with how loud it is. Resolves with a stop function, or null when the
 * microphone isn't available or allowed.
 */
export async function startMicLevel(onLevel: (level: number) => void): Promise<(() => void) | null> {
  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) return null
  let stream: MediaStream
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } })
  } catch {
    return null
  }
  const ctx = new AudioContext()
  const analyser = ctx.createAnalyser()
  analyser.fftSize = 512
  ctx.createMediaStreamSource(stream).connect(analyser)
  const samples = new Float32Array(analyser.fftSize)
  let frame = 0
  // Root-mean-square loudness, scaled so normal speech lands around 0.5-1.
  const tick = () => {
    analyser.getFloatTimeDomainData(samples)
    let sum = 0
    for (const s of samples) sum += s * s
    const rms = Math.sqrt(sum / samples.length)
    onLevel(Math.min(1, rms * 9))
    frame = requestAnimationFrame(tick)
  }
  frame = requestAnimationFrame(tick)
  return () => {
    cancelAnimationFrame(frame)
    for (const t of stream.getTracks()) t.stop()
    void ctx.close()
  }
}
