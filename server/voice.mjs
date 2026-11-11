// Jarvis's voice settings: checking a choice sent from the page, the voice
// list the sample data uses, and a made-up WAV for sample Play buttons.
// The real voices and samples come from Jarvis (server/sources/live.mjs).

/** Slowest and fastest Jarvis may talk (Kokoro's speed). */
export const SPEED_MIN = 0.7
export const SPEED_MAX = 1.4

/** Kokoro v1.0's English voices, with friendly names (sample data). */
export const SAMPLE_VOICES = [
  ['af_heart', 'Heart'], ['af_bella', 'Bella'], ['af_nicole', 'Nicole'], ['af_sarah', 'Sarah'], ['af_sky', 'Sky'],
  ['am_michael', 'Michael'], ['am_fenrir', 'Fenrir'], ['am_puck', 'Puck'], ['am_adam', 'Adam'], ['am_eric', 'Eric'],
  ['bf_emma', 'Emma'], ['bf_isabella', 'Isabella'], ['bf_alice', 'Alice'], ['bf_lily', 'Lily'],
  ['bm_george', 'George'], ['bm_lewis', 'Lewis'], ['bm_fable', 'Fable'], ['bm_daniel', 'Daniel'],
].map(([id, name]) => ({ id, name, accent: id.startsWith('b') ? 'gb' : 'us', gender: id[1] === 'f' ? 'f' : 'm' }))

/** A voice id as Kokoro names them: two letters, underscore, a name. */
function isVoiceId(value) {
  return typeof value === 'string' && /^[a-z]{2}_[a-z0-9]{1,24}$/.test(value)
}

/**
 * Turns what the page sent into a voice choice, or an error message.
 * Speed is 0.7 to 1.4; a blend needs a second voice and a mix between 0 and 1.
 */
export function checkVoiceChoice(body) {
  if (!isVoiceId(body?.voice)) return { error: 'Send a voice id like "bm_george"' }
  const speed = Number(body.speed ?? 1)
  if (!Number.isFinite(speed) || speed < SPEED_MIN || speed > SPEED_MAX) {
    return { error: `Speed goes from ${SPEED_MIN} to ${SPEED_MAX}` }
  }
  let blend = null
  if (body.blend) {
    const mix = Number(body.blend.mix)
    if (!isVoiceId(body.blend.voice2)) return { error: 'A blend needs a second voice id' }
    if (!Number.isFinite(mix) || mix <= 0 || mix >= 1) return { error: 'The blend mix goes between 0 and 1' }
    blend = { voice2: body.blend.voice2, mix }
  }
  return { choice: { voice: body.voice, speed, blend } }
}

/** Reads a voice choice from a sample URL's query (?voice=&speed=&voice2=&mix=). */
export function choiceFromQuery(params) {
  const voice2 = params.get('voice2')
  const body = { voice: params.get('voice'), speed: params.get('speed') ?? 1 }
  if (voice2) body.blend = { voice2, mix: params.get('mix') }
  return checkVoiceChoice(body)
}

/** A number from a string, so each pretend voice gets its own pitch. */
function hash(text) {
  let h = 0
  for (const ch of text) h = (h * 31 + ch.charCodeAt(0)) >>> 0
  return h
}

/**
 * A short made-up "voice": three soft rising notes as a 16-bit mono WAV,
 * pitched by the voice (and blend) and quicker at higher speeds. Lets the
 * sample page's Play buttons make a sound with no Kokoro.
 */
export function sampleWav(choice) {
  const rate = 16000
  const base = 140 + (hash(choice.voice) % 160) + (choice.blend ? (hash(choice.blend.voice2) % 60) * choice.blend.mix : 0)
  const noteSamples = Math.round((rate * 0.22) / choice.speed)
  const total = noteSamples * 3
  const bytes = new Uint8Array(44 + total * 2)
  const view = new DataView(bytes.buffer)
  const text = (at, s) => { for (let i = 0; i < s.length; i++) view.setUint8(at + i, s.charCodeAt(i)) }
  text(0, 'RIFF'); view.setUint32(4, 36 + total * 2, true); text(8, 'WAVE')
  text(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true)
  view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true)
  text(36, 'data'); view.setUint32(40, total * 2, true)
  for (let i = 0; i < total; i++) {
    const note = Math.floor(i / noteSamples)
    const within = (i % noteSamples) / noteSamples
    // Fade each note in and out so it doesn't click.
    const envelope = Math.sin(Math.PI * within)
    const freq = base * [1, 1.25, 1.5][note]
    view.setInt16(44 + i * 2, Math.round(Math.sin((2 * Math.PI * freq * i) / rate) * envelope * 9000), true)
  }
  return bytes
}
